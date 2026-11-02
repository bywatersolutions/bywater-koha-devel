package Koha::Item::Availability::Checkout;

# Copyright 2026 Koha Development Team
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

use C4::Circulation ();
use C4::Context;
use Koha::DateUtils qw( dt_from_string output_pref );
use Koha::Exception;
use Koha::Exceptions;
use Koha::Item::Availability::Checkout::Result;

=head1 NAME

Koha::Item::Availability::Checkout - Checkout availability validation for items

=head1 SYNOPSIS

    my $availability = $item->checkout_availability(
        {
            patron          => $patron,
            user            => $logged_in_user,
            library         => $library_id,
            interface       => 'intranet',
            due_date        => $due_date,
            onsite_checkout => 0,
            overrides       => { patron_debarred => 1 },    # or { any => 1 }
        }
    );

    if ( !$availability->available ) {
        # $availability->blockers
    } elsif ( $availability->needs_confirmation ) {
        # $availability->confirmations, $availability->as_token
    }

    # Legacy keys for AddIssue's confirmations/forced parameters
    my $overrides = $availability->legacy_override_params;

=head1 DESCRIPTION

This class answers the question I<can this item be checked out to this
patron, by this user?> without changing anything in the database.

It wraps L<C4::Circulation/CanBookBeIssued> and translates its four
hashes (I<issuingimpossible>, I<needsconfirmation>, I<alerts> and
I<messages>) into a L<Koha::Item::Availability::Checkout::Result>, where:

=over

=item * every UPPERCASE key is renamed to a snake_case key (see L</KEYS>)

=item * the data CanBookBeIssued stores in sibling keys (C<issued_*>,
C<res*>, C<current_loan_count>, C<circulation_rule_TOO_MANY>,
C<item_notforloan>, C<branch_to_return>, ...) becomes the payload of the
key it relates to

=item * the business rules that callers used to apply on top of
CanBookBeIssued are applied here (see L</RULES>)

=item * payloads carry ids instead of objects (e.g. C<recall_id>,
C<booking_id>, C<patron_id>), so callers can fetch or embed them, and dates
as RFC3339 strings

=back

It mirrors L<Koha::Item::Availability::Checkin>.

=head1 RULES

The following rules used to live in F<circ/circulation.pl>,
F<circulation.tt> and L<Koha::REST::V1::Checkouts>. They are applied in this
order.

=head2 Statistical patrons

CanBookBeIssued records a I<localuse> statistic (and updates the item's
I<datelastseen>) when the patron belongs to a statistical category
(I<category_type> C<X>). An availability check must not write anything, so
statistical patrons are detected up front and the C<statistical_patron>
blocker is returned without calling CanBookBeIssued.

=head2 No open days

When the due date cannot be calculated because the library calendar has no
open days, the C<no_open_days> blocker is returned (as F<circ/circulation.pl>
did).

=head2 Staff interface (I<interface> = C<intranet>)

=over

=item 1. B<AllowHoldCheckoutOverride>: when disabled, the C<reserved>,
C<reserve_waiting>, C<transferred> and C<processing> confirmations become
blockers.

=item 2. B<OnSiteCheckoutsForce>: for on-site checkouts, when enabled, all
blockers but C<unknown_barcode>, C<no_open_days>, C<booked_to_another> and
C<statistical_patron> are relaxed: they become warnings and are recorded as
forced (see L<Koha::Item::Availability::Checkout::Result/forced>), so they
are passed to AddIssue's I<forced> parameter.

=item 3. B<circulate.force_checkout>: only the C<high_holds> and
C<additional_materials> confirmations can be confirmed without the
I<force_checkout> permission. When the user lacks it (or no user is passed),
any other confirmation becomes a blocker. This mirrors the I<Cannot check
out> box on the legacy checkout page, which only offered a confirmation form
to users with I<force_checkout>, or when a high holds or accompanying
materials confirmation was displayed.

The legacy page, in that last case, actually let the user confirm everything
displayed alongside (e.g. a debt), and offered the materials form whenever
the item had materials, even with I<CircConfirmItemParts> disabled. This
class evaluates the permission per key instead.

=item 4. B<overrides>: when the user has the I<force_checkout> permission,
the blockers listed in the I<overrides> parameter (or all of them, with
C<any>) are relaxed like I<OnSiteCheckoutsForce> does: they become warnings
and are recorded as forced (see
L<Koha::Item::Availability::Checkout::Result/forced>), so they are passed to
AddIssue's I<forced> parameter. C<unknown_barcode>, C<no_open_days> and
C<statistical_patron> can't be overridden, nor can the hold keys when
I<AllowHoldCheckoutOverride> is disabled. This replaces the I<forceallow>
parameter of F<circ/circulation.pl>, and follows the I<overrides> parameter
of the hold availability classes. Confirmations are not affected, they
still need to be confirmed.

=back

=head2 Public interface (I<interface> = C<opac>)

These are the rules from the public checkout route
(I<OpacTrustedCheckout>, C<Koha::REST::V1::Checkouts::_check_availability>):

=over

=item * C<too_many>, C<issued_to_another> and C<age_restriction>
confirmations become blockers.

=item * B<AllowItemsOnHoldCheckoutSCO>: C<0> blocks pending and waiting
holds, C<1> allows pending holds but blocks waiting, in transit and in
processing holds, C<2> allows all of them. Allowed hold confirmations are
dropped.

=item * Payloads exposing other patrons are reduced: C<issued_to_another>
and the hold keys get C<1>, C<not_for_loan> / C<not_for_loan_forcing> lose
the item's I<notforloan> value. Going beyond the legacy route,
C<recalled>, C<returned_from_another>, C<booked_to_another> and
C<booked_due_date_clash> get C<1>.

=back

The I<force_checkout>, I<overrides>, I<AllowHoldCheckoutOverride> and
I<OnSiteCheckoutsForce> rules don't apply to the public interface.

=head1 KEYS

Blockers and confirmations. The I<Legacy> column is the CanBookBeIssued key.
Unless stated otherwise, confirmations require I<circulate.force_checkout>
in the staff interface (see L</RULES>).

=head2 Patron

=over

=item C<statistical_patron> (I<STATS>): blocker. The patron is a statistical
patron. Payload: C<1>.

=item C<gone_no_address> (I<GNA>): blocker. Payload: C<1>.

=item C<card_lost> (I<CARD_LOST>): blocker. Payload: C<1>.

=item C<patron_expired> (I<EXPIRED>): blocker. Payload: C<1>.

=item C<patron_debarred> (I<DEBARRED>): blocker. Payload: C<1>.

=item C<patron_debarred_until> (I<USERBLOCKEDWITHENDDATE>): blocker, along
with C<patron_debarred>. Payload: the restriction end date.

=item C<patron_debarred_indefinitely> (I<USERBLOCKEDNOENDDATE>): blocker,
along with C<patron_debarred>. Payload: C<9999-12-31>.

=item C<patron_has_overdues> (I<USERBLOCKEDOVERDUE>): blocker or
confirmation depending on I<OverduesBlockCirc>. Payload: number of overdues.

=item C<debt> (I<DEBT>): blocker, or confirmation with I<AllowFineOverride>
or I<AllFinesNeedOverride>. Payload: the amount.

=item C<debt_guarantees> (I<DEBT_GUARANTEES>),
C<debt_guarantors> (I<DEBT_GUARANTORS>),
C<debt_linked_accounts> (I<DEBT_LINKED_ACCOUNTS>): same as C<debt>.
Payload: the amount.

=item C<too_many> (I<TOO_MANY>): blocker, or confirmation with
I<AllowTooManyOverride>. Payload:
C<< { reason, count, max_allowed, circulation_rule } >> where I<reason> is
C<TOO_MANY_CHECKOUTS>, C<TOO_MANY_ONSITE_CHECKOUTS> or C<NO_RULE_DEFINED>.

=item C<patron_cant> (I<PATRON_CANT>): confirmation, the circulation rules
allow no checkouts at all. Payload: C<< { circulation_rule } >>.

=item C<patron_not_same_branch> (I<BORRNOTSAMEBRANCH>): confirmation
(I<IndependentBranches>). Payload: the patron's library id.

=item C<age_restriction> (I<AGE_RESTRICTION>): blocker, or confirmation with
I<AgeRestrictionOverride>. Payload: the age restriction.

=back

=head2 Item

=over

=item C<unknown_barcode> (I<UNKNOWN_BARCODE>): blocker. Not expected, as an
item is required. Payload: C<1>.

=item C<not_for_loan> (I<NOT_FOR_LOAN>): blocker. Payload:
C<< { notforloan } >> (item status) or C<< { itemtype } >> (item type not for
loan).

=item C<not_for_loan_forcing> (I<NOT_FOR_LOAN_FORCING>): confirmation, with
I<AllowNotForLoanOverride>. Payload: as C<not_for_loan>.

=item C<withdrawn> (I<WTHDRAWN>): blocker. Payload: C<1>.

=item C<item_restricted> (I<RESTRICTED>): blocker. Payload: C<1>.

=item C<item_lost> (I<ITEM_LOST>): confirmation with I<IssueLostItem> set to
C<confirm> (warning with C<alert>). Payload: the lost status description.

=item C<item_not_same_branch> (I<ITEMNOTSAMEBRANCH>): blocker
(I<IndependentBranches>). Payload: C<< { library_id } >>.

=item C<additional_materials> (I<ADDITIONAL_MATERIALS>): confirmation
(I<CircConfirmItemParts>). Does B<not> require I<force_checkout>. Payload: the
materials.

=item C<rental_charge> (I<RENTALCHARGE>): confirmation
(I<RentalFeesCheckoutConfirmation>). Payload: the amount.

=item C<high_holds> (I<HIGHHOLDS>): confirmation (warning when
I<override_high_holds> is passed) with I<decreaseLoanHighHolds>. Does
B<not> require I<force_checkout>. Payload:
C<< { num_holds, duration, returndate } >>, I<returndate> as RFC3339.

=item C<supply_ill> (I<SUPPLY_ILL>): confirmation, checking out a supply ILL
to an ILL partner. Payload: C<< { iso18626_request_id } >>.

=back

=head2 Current and past checkouts

=over

=item C<issued_to_another> (I<ISSUED_TO_ANOTHER>): confirmation. Payload:
C<< { patron_id, firstname, surname, cardnumber } >> of the current borrower.

=item C<return_impossible> (I<RETURN_IMPOSSIBLE>): blocker, the item is
checked out to another patron and cannot be returned here. Payload:
C<< { library_id } >> where it must be returned.

=item C<renew_issue> (I<RENEW_ISSUE>): confirmation, the item is checked out
to this patron and will be renewed. Payload: C<1>.

=item C<no_more_renewals> (I<NO_MORE_RENEWALS>): blocker. Payload: C<1>.

=item C<no_renewal_for_onsite_checkouts>
(I<NO_RENEWAL_FOR_ONSITE_CHECKOUTS>): blocker. Payload: C<1>.

=item C<current_checkout> (I<CURRENTISSUE>): confirmation
(I<CheckPrevCheckout>), the patron has this title checked out. Payload: C<1>.

=item C<previous_checkout> (I<PREVISSUE>): confirmation
(I<CheckPrevCheckout>). Payload: C<1>.

=item C<biblio_already_issued> (I<BIBLIO_ALREADY_ISSUED>): confirmation
(I<AllowMultipleIssuesOnABiblio> disabled). Payload: C<1>.

=back

=head2 Holds, recalls and bookings

=over

=item C<reserved> (I<RESERVED>), C<reserve_waiting> (I<RESERVE_WAITING>),
C<transferred> (I<TRANSFERRED>), C<processing> (I<PROCESSING>):
confirmation, the item is on hold for another patron. Payload:
C<< { hold_id, patron_id, firstname, surname, cardnumber,
pickup_library_id, hold_date, waiting_date } >>.

=item C<recalled> (I<RECALLED>): confirmation. Payload: C<< { recall_id } >>.

=item C<recalled_in_transit> (I<RECALLED_INTRANSIT>): blocker. Payload: the
pickup library id.

=item C<booked_early> (I<BOOKED_EARLY>): confirmation. Payload:
C<< { booking_id } >>.

=item C<booked_to_another> (I<BOOKED_TO_ANOTHER>): confirmation when the
booking starts before the due date, blocker when the loan falls inside it.
Payload: C<< { booking_id } >>.

=item C<booked_due_date_clash> (I<BOOKED_DUE_DATE_CLASH>): confirmation.
Payload: C<< { booking_id } >> of the next booking.

=back

=head2 Dates

=over

=item C<invalid_date> (I<INVALID_DATE>): confirmation, the due date is in the
past. Payload: C<< { due_date } >> (RFC3339).

=item C<no_open_days> (I<NO_OPEN_DAYS>): blocker. Payload: C<1>.

=back

=head2 Warnings

Warnings (CanBookBeIssued's alerts and messages) never prevent the checkout:

=over

=item C<other_charges> (I<OTHER_CHARGES>): unpaid non-blocking charges.

=item C<item_lost> (I<ITEM_LOST>): see above.

=item C<high_holds> (I<HIGHHOLDS>): see above.

=item C<returned_from_another> (I<RETURNED_FROM_ANOTHER>): the item will be
returned from another patron (I<AutoReturnCheckedOutItems>). Payload:
C<< { patron_id } >>.

=item C<linked_account_hold_pickup> (I<LINKED_ACCOUNT_HOLD_PICKUP>): the
hold belongs to a linked account. Payload:
C<< { hold_id, patron_id } >>.

=item C<booked> (I<BOOKED>): the patron has a current booking. Payload:
C<< { booking_id } >>.

=item C<onsite_checkout_will_be_switched>
(I<ONSITE_CHECKOUT_WILL_BE_SWITCHED>). Payload: C<1>.

=item C<recall_for_patron> (I<RECALLED> message): the item fills a recall
placed by this patron. Payload: the recall id.

=back

=head1 API

=head2 Constants

=head3 KEY_MAP

Maps CanBookBeIssued blocker and confirmation keys to the snake_case keys.

=cut

use constant KEY_MAP => {
    ADDITIONAL_MATERIALS            => 'additional_materials',
    AGE_RESTRICTION                 => 'age_restriction',
    BIBLIO_ALREADY_ISSUED           => 'biblio_already_issued',
    BOOKED_DUE_DATE_CLASH           => 'booked_due_date_clash',
    BOOKED_EARLY                    => 'booked_early',
    BOOKED_TO_ANOTHER               => 'booked_to_another',
    BORRNOTSAMEBRANCH               => 'patron_not_same_branch',
    CARD_LOST                       => 'card_lost',
    CURRENTISSUE                    => 'current_checkout',
    DEBARRED                        => 'patron_debarred',
    DEBT                            => 'debt',
    DEBT_GUARANTEES                 => 'debt_guarantees',
    DEBT_GUARANTORS                 => 'debt_guarantors',
    DEBT_LINKED_ACCOUNTS            => 'debt_linked_accounts',
    EXPIRED                         => 'patron_expired',
    GNA                             => 'gone_no_address',
    HIGHHOLDS                       => 'high_holds',
    INVALID_DATE                    => 'invalid_date',
    ISSUED_TO_ANOTHER               => 'issued_to_another',
    ITEMNOTSAMEBRANCH               => 'item_not_same_branch',
    ITEM_LOST                       => 'item_lost',
    NOT_FOR_LOAN                    => 'not_for_loan',
    NOT_FOR_LOAN_FORCING            => 'not_for_loan_forcing',
    NO_MORE_RENEWALS                => 'no_more_renewals',
    NO_OPEN_DAYS                    => 'no_open_days',
    NO_RENEWAL_FOR_ONSITE_CHECKOUTS => 'no_renewal_for_onsite_checkouts',
    PATRON_CANT                     => 'patron_cant',
    PREVISSUE                       => 'previous_checkout',
    PROCESSING                      => 'processing',
    RECALLED                        => 'recalled',
    RECALLED_INTRANSIT              => 'recalled_in_transit',
    RENEW_ISSUE                     => 'renew_issue',
    RENTALCHARGE                    => 'rental_charge',
    RESERVED                        => 'reserved',
    RESERVE_WAITING                 => 'reserve_waiting',
    RESTRICTED                      => 'item_restricted',
    RETURN_IMPOSSIBLE               => 'return_impossible',
    STATS                           => 'statistical_patron',
    SUPPLY_ILL                      => 'supply_ill',
    TOO_MANY                        => 'too_many',
    TRANSFERRED                     => 'transferred',
    UNKNOWN_BARCODE                 => 'unknown_barcode',
    USERBLOCKEDNOENDDATE            => 'patron_debarred_indefinitely',
    USERBLOCKEDOVERDUE              => 'patron_has_overdues',
    USERBLOCKEDWITHENDDATE          => 'patron_debarred_until',
    WTHDRAWN                        => 'withdrawn',
};

=head3 WARNING_KEY_MAP

Maps CanBookBeIssued alert and message keys to the snake_case warning keys.

=cut

use constant WARNING_KEY_MAP => {
    BOOKED                           => 'booked',
    HIGHHOLDS                        => 'high_holds',
    ITEM_LOST                        => 'item_lost',
    LINKED_ACCOUNT_HOLD_PICKUP       => 'linked_account_hold_pickup',
    ONSITE_CHECKOUT_WILL_BE_SWITCHED => 'onsite_checkout_will_be_switched',
    OTHER_CHARGES                    => 'other_charges',
    RECALLED                         => 'recall_for_patron',
    RETURNED_FROM_ANOTHER            => 'returned_from_another',
};

=head3 DATA_KEYS

CanBookBeIssued keys that carry data for another key. They are folded into
that key's payload.

=cut

use constant DATA_KEYS => [
    qw(
        branch_to_return
        circulation_rule_PATRON_CANT
        circulation_rule_TOO_MANY
        current_loan_count
        iso18626_payload_supplyill
        issued_borrowernumber
        issued_cardnumber
        issued_firstname
        issued_surname
        item_notforloan
        itemhomebranch
        itemtype_notforloan
        max_loans_allowed
        resborrowernumber
        resbranchcode
        rescardnumber
        reserve_id
        resfirstname
        resreservedate
        ressurname
        reswaitingdate
    )
];

=head3 HOLD_KEYS

The keys for items on hold for another patron.

=cut

use constant HOLD_KEYS => [qw( reserved reserve_waiting transferred processing )];

=head3 CONFIRMATIONS_WITHOUT_FORCE_CHECKOUT

Confirmations that can be confirmed in the staff interface without the
I<circulate.force_checkout> permission.

=cut

use constant CONFIRMATIONS_WITHOUT_FORCE_CHECKOUT => [qw( additional_materials high_holds )];

=head3 ONSITE_FORCE_BLOCKERS

Blockers that I<OnSiteCheckoutsForce> does not relax.

=cut

use constant ONSITE_FORCE_BLOCKERS => [qw( booked_to_another no_open_days statistical_patron unknown_barcode )];

=head3 UNFORCEABLE_BLOCKERS

Blockers that the I<overrides> parameter does not override.

=cut

use constant UNFORCEABLE_BLOCKERS => [qw( no_open_days statistical_patron unknown_barcode )];

=head2 Class methods

=head3 check

    my $availability = Koha::Item::Availability::Checkout->check(
        $item,
        {
            patron              => $patron,             # required
            user                => $user,
            library             => $library_id,
            interface           => 'intranet',          # or 'opac'
            due_date            => $due_date,
            onsite_checkout     => 0,
            ignore_reserves     => 0,
            override_high_holds => 0,
            in_process          => 0,
            overrides           => {},
        }
    );

Validates checkout availability for an item. Nothing is written to the
database.

Parameters:

=over

=item I<patron>: the L<Koha::Patron> the item would be checked out to
(required).

=item I<user>: the L<Koha::Patron> performing the checkout. Used for the
I<force_checkout> permission check and bound to the confirmation token.
Defaults to I<patron> for the C<opac> interface.

=item I<library>: the library id where the checkout takes place. Defaults to
the current user environment's library (C<C4::Context-E<gt>userenv>).

=item I<interface>: C<intranet> (default) or C<opac>. Selects the rules
applied on top of CanBookBeIssued (see L</RULES>).

=item I<due_date>: requested due date (DateTime or string). Defaults to the
calculated due date.

=item I<onsite_checkout>: the checkout is an on-site checkout.

=item I<ignore_reserves>: skip the holds check.

=item I<override_high_holds>: report high holds as a warning instead of a
confirmation (the loan period will not be decreased).

=item I<in_process>: a checkout session is in process (see
I<IssuingInProcess>), debts are not checked.

=item I<overrides>: hashref of blocker keys to override, or C<< { any => 1 } >>
for all of them. Only honoured if the I<user> has the I<force_checkout>
permission (see L</RULES>).

=back

CanBookBeIssued reads the library and the superlibrarian status from the
current user environment (C<C4::Context-E<gt>userenv>). The I<library>
parameter overrides the library for the duration of the check.

Returns a L<Koha::Item::Availability::Checkout::Result> with the I<item>,
I<patron> and I<user> context set.

=cut

sub check {
    my ( $class, $item, $params ) = @_;

    my $patron = $params->{patron}
        or Koha::Exceptions::MissingParameter->throw( parameter => 'patron' );

    my $interface = $params->{interface} // 'intranet';
    Koha::Exceptions::BadParameter->throw( parameter => 'interface' )
        unless $interface eq 'intranet' || $interface eq 'opac';

    my $user = $params->{user} // ( $interface eq 'opac' ? $patron : undef );

    my $onsite_checkout = $params->{onsite_checkout} ? 1 : 0;

    my $due_date = $params->{due_date};
    $due_date = dt_from_string($due_date)
        if defined $due_date && !blessed $due_date;

    # CanBookBeIssued (and the routines it calls) read the library from the
    # user environment
    my $userenv = C4::Context->userenv // {};
    local $userenv->{branch} = $params->{library} // $userenv->{branch};

    my $result = Koha::Item::Availability::Checkout::Result->new();
    $result->set_context( item   => $item );
    $result->set_context( patron => $patron );
    $result->set_context( user   => $user ) if $user;

    # CanBookBeIssued records a statistic for statistical patrons. Detect
    # them beforehand so checking availability has no side effects.
    if ( $patron->category->category_type eq 'X' && $item->barcode ) {
        $result->add_blocker( statistical_patron => 1 );
        return $result;
    }

    my ( $impossible, $confirmation, $alerts, $messages );
    try {
        ( $impossible, $confirmation, $alerts, $messages ) = C4::Circulation::CanBookBeIssued(
            $patron,
            undef,
            $due_date,
            $params->{in_process}      ? 1 : 0,
            $params->{ignore_reserves} ? 1 : 0,
            {
                item                => $item,
                onsite_checkout     => $onsite_checkout,
                override_high_holds => $params->{override_high_holds} ? 1 : 0,
            }
        );
    } catch {
        if ( blessed $_ && $_->isa('Koha::Exceptions::Calendar::NoOpenDays') ) {
            $impossible = { NO_OPEN_DAYS => 1 };
        } elsif ( blessed $_ && $_->can('rethrow') ) {
            $_->rethrow;
        } else {
            Koha::Exception->throw("$_");
        }
    };

    $class->_map_legacy_results(
        $result,
        {
            impossible   => $impossible   // {},
            confirmation => $confirmation // {},
            alerts       => $alerts       // {},
            messages     => $messages     // {},
        }
    );

    if ( $interface eq 'opac' ) {
        $class->_apply_public_rules($result);
    } else {
        $class->_apply_hold_override_rule($result);
        $class->_apply_onsite_force_rule($result)
            if $onsite_checkout && C4::Context->preference('OnSiteCheckoutsForce');
        $class->_apply_force_checkout_rule( $result, $user );
        $class->_apply_overrides_rule( $result, $user, $params->{overrides} )
            if $params->{overrides} && %{ $params->{overrides} };
    }

    return $result;
}

=head3 key_from_legacy

    my $key = Koha::Item::Availability::Checkout->key_from_legacy('DEBT'); # debt

Returns the snake_case key for a CanBookBeIssued blocker or confirmation key.
Unknown keys are lowercased.

=cut

sub key_from_legacy {
    my ( $class, $legacy_key ) = @_;
    return KEY_MAP->{$legacy_key} // lc $legacy_key;
}

=head3 legacy_from_key

    my $legacy_key = Koha::Item::Availability::Checkout->legacy_from_key('debt'); # DEBT

Returns the CanBookBeIssued key for a snake_case blocker or confirmation key,
as expected by AddIssue's I<confirmations> and I<forced> parameters.
Unknown keys are uppercased.

=cut

sub legacy_from_key {
    my ( $class, $key ) = @_;
    my %legacy = reverse %{ +KEY_MAP };
    return $legacy{$key} // uc $key;
}

=head2 Internal methods

=head3 _map_legacy_results

Translates CanBookBeIssued's hashes into the result object.

=cut

sub _map_legacy_results {
    my ( $class, $result, $legacy ) = @_;

    my %is_data_key = map { $_ => 1 } @{ +DATA_KEYS };

    # CanBookBeIssued doesn't always put the data next to the key it relates
    # to (e.g. circulation_rule_TOO_MANY is a confirmation even when TOO_MANY
    # is a blocker), so look both places up
    my $data = { %{ $legacy->{confirmation} }, %{ $legacy->{impossible} } };

    for my $legacy_key ( sort keys %{ $legacy->{impossible} } ) {
        next if $is_data_key{$legacy_key};
        $result->add_blocker(
            $class->key_from_legacy($legacy_key) => $class->_payload( $legacy_key, $legacy->{impossible}, $data ) );
    }

    for my $legacy_key ( sort keys %{ $legacy->{confirmation} } ) {
        next if $is_data_key{$legacy_key};
        $result->add_confirmation(
            $class->key_from_legacy($legacy_key) => $class->_payload( $legacy_key, $legacy->{confirmation}, $data ) );
    }

    for my $legacy_key ( sort( keys %{ $legacy->{alerts} } ), sort( keys %{ $legacy->{messages} } ) ) {
        my $value = $legacy->{alerts}->{$legacy_key} // $legacy->{messages}->{$legacy_key};
        $result->add_warning(
            ( WARNING_KEY_MAP->{$legacy_key} // lc $legacy_key ) => $class->_warning_payload( $legacy_key, $value ) );
    }

    return $result;
}

=head3 _payload

Builds the payload for a CanBookBeIssued key, folding its related data keys.
I<$own> is the hash the key comes from, I<$data> both hashes merged.

=cut

sub _payload {
    my ( $class, $legacy_key, $own, $data ) = @_;

    my $value = $own->{$legacy_key};

    if ( $legacy_key eq 'ISSUED_TO_ANOTHER' ) {
        return {
            patron_id  => $data->{issued_borrowernumber},
            firstname  => $data->{issued_firstname},
            surname    => $data->{issued_surname},
            cardnumber => $data->{issued_cardnumber},
        };
    }

    if ( grep { $legacy_key eq $_ } qw( RESERVED RESERVE_WAITING TRANSFERRED PROCESSING ) ) {
        return {
            hold_id           => $data->{reserve_id},
            patron_id         => $data->{resborrowernumber},
            firstname         => $data->{resfirstname},
            surname           => $data->{ressurname},
            cardnumber        => $data->{rescardnumber},
            pickup_library_id => $data->{resbranchcode},
            hold_date         => $data->{resreservedate},
            waiting_date      => $data->{reswaitingdate},
        };
    }

    if ( $legacy_key eq 'TOO_MANY' ) {
        return {
            reason           => $value,
            count            => $data->{current_loan_count},
            max_allowed      => $data->{max_loans_allowed},
            circulation_rule => $data->{circulation_rule_TOO_MANY},
        };
    }

    if ( $legacy_key eq 'PATRON_CANT' ) {
        return { circulation_rule => $data->{circulation_rule_PATRON_CANT} };
    }

    if ( $legacy_key eq 'NOT_FOR_LOAN' || $legacy_key eq 'NOT_FOR_LOAN_FORCING' ) {

        # Both live next to the key they relate to
        return exists $own->{item_notforloan}
            ? { notforloan => $own->{item_notforloan} }
            : { itemtype   => $own->{itemtype_notforloan} };
    }

    if ( $legacy_key eq 'ITEMNOTSAMEBRANCH' ) {
        return { library_id => $data->{itemhomebranch} };
    }

    if ( $legacy_key eq 'RETURN_IMPOSSIBLE' ) {
        return { library_id => $data->{branch_to_return} };
    }

    if ( $legacy_key eq 'SUPPLY_ILL' ) {
        return { iso18626_request_id => $data->{iso18626_payload_supplyill} };
    }

    if ( $legacy_key eq 'HIGHHOLDS' ) {
        return $class->_high_holds_payload($value);
    }

    if ( $legacy_key eq 'RECALLED' ) {
        return { recall_id => $value->id };
    }

    if ( grep { $legacy_key eq $_ } qw( BOOKED_EARLY BOOKED_TO_ANOTHER BOOKED_DUE_DATE_CLASH ) ) {
        return { booking_id => $value->id };
    }

    if ( $legacy_key eq 'INVALID_DATE' ) {
        return { due_date => output_pref( { dt => $value, dateformat => 'rfc3339' } ) };
    }

    return $value;
}

=head3 _warning_payload

Builds the payload for a CanBookBeIssued alert or message key.

=cut

sub _warning_payload {
    my ( $class, $legacy_key, $value ) = @_;

    if ( $legacy_key eq 'RETURNED_FROM_ANOTHER' ) {
        return { patron_id => $value->{patron}->id };
    }

    if ( $legacy_key eq 'LINKED_ACCOUNT_HOLD_PICKUP' ) {
        return { hold_id => $value->{reserve_id}, patron_id => $value->{hold_patron_id} };
    }

    if ( $legacy_key eq 'HIGHHOLDS' ) {
        return $class->_high_holds_payload($value);
    }

    if ( $legacy_key eq 'BOOKED' ) {
        return { booking_id => $value->id };
    }

    return $value;
}

=head3 _high_holds_payload

Returns the high holds payload with I<returndate> as an RFC3339 string.

=cut

sub _high_holds_payload {
    my ( $class, $value ) = @_;

    return $value unless ref $value eq 'HASH' && blessed $value->{returndate};

    return { %{$value}, returndate => output_pref( { dt => $value->{returndate}, dateformat => 'rfc3339' } ) };
}

=head3 _apply_hold_override_rule

Promotes hold confirmations to blockers when I<AllowHoldCheckoutOverride> is
disabled.

=cut

sub _apply_hold_override_rule {
    my ( $class, $result ) = @_;

    return if C4::Context->preference('AllowHoldCheckoutOverride');

    $result->promote_confirmation($_) for @{ +HOLD_KEYS };

    return;
}

=head3 _apply_onsite_force_rule

Relaxes blockers for on-site checkouts when I<OnSiteCheckoutsForce> is
enabled.

=cut

sub _apply_onsite_force_rule {
    my ( $class, $result ) = @_;

    my %keep = map { $_ => 1 } @{ +ONSITE_FORCE_BLOCKERS };
    for my $key ( keys %{ $result->blockers } ) {
        $result->relax_blocker($key) unless $keep{$key};
    }

    return;
}

=head3 _apply_force_checkout_rule

Promotes the confirmations that require I<circulate.force_checkout> to
blockers when the user lacks that permission.

=cut

sub _apply_force_checkout_rule {
    my ( $class, $result, $user ) = @_;

    return if $user && $user->has_permission( { circulate => 'force_checkout' } );

    my %allowed = map { $_ => 1 } @{ +CONFIRMATIONS_WITHOUT_FORCE_CHECKOUT };
    for my $key ( keys %{ $result->confirmations } ) {
        $result->promote_confirmation($key) unless $allowed{$key};
    }

    return;
}

=head3 _apply_overrides_rule

Relaxes the overridden blockers when the user has the
I<circulate.force_checkout> permission. Holds are not overridden when
I<AllowHoldCheckoutOverride> is disabled.

=cut

sub _apply_overrides_rule {
    my ( $class, $result, $user, $overrides ) = @_;

    return unless $user && $user->has_permission( { circulate => 'force_checkout' } );

    my %keep = map { $_ => 1 } @{ +UNFORCEABLE_BLOCKERS };

    # AllowHoldCheckoutOverride wins over the user's overrides
    unless ( C4::Context->preference('AllowHoldCheckoutOverride') ) {
        $keep{$_} = 1 for @{ +HOLD_KEYS };
    }

    for my $key ( keys %{ $result->blockers } ) {
        next                         if $keep{$key};
        $result->relax_blocker($key) if $overrides->{any} || $overrides->{$key};
    }

    return;
}

=head3 _apply_public_rules

Applies the public (I<OpacTrustedCheckout>) rules.

=cut

sub _apply_public_rules {
    my ( $class, $result ) = @_;

    my @should_block = qw( too_many issued_to_another age_restriction );

    # AllowItemsOnHoldCheckoutSCO:
    #   0 = block pending and waiting holds (default)
    #   1 = allow pending holds, block waiting/transit/processing holds
    #   2 = allow pending and waiting/transit/processing holds
    my $hold_pref = C4::Context->preference('AllowItemsOnHoldCheckoutSCO') || 0;
    push @should_block, 'reserved'                                   if $hold_pref < 1;
    push @should_block, qw( reserve_waiting transferred processing ) if $hold_pref < 2;

    $result->promote_confirmation($_) for @should_block;

    # The remaining hold confirmations are allowed by the policy
    delete $result->confirmations->{$_} for @{ +HOLD_KEYS };

    # Don't expose other patrons' data
    for my $set ( $result->blockers, $result->confirmations, $result->warnings ) {
        for my $key (
            qw( issued_to_another recalled returned_from_another booked_to_another booked_due_date_clash ),
            @{ +HOLD_KEYS }
            )
        {
            $set->{$key} = 1 if exists $set->{$key};
        }
        for my $key (qw( not_for_loan not_for_loan_forcing )) {
            delete $set->{$key}->{notforloan} if ref $set->{$key} eq 'HASH';
        }
    }

    return;
}

=head1 AUTHOR

Koha Development Team <https://koha-community.org/>

=cut

1;
