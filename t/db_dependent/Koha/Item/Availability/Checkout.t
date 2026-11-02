#!/usr/bin/perl

# Copyright 2026 Koha Development team
#
# This file is part of Koha
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

use Test::More tests => 18;
use Test::NoWarnings;
use Test::Exception;
use Test::MockModule;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::ActionLogs;
use Koha::CirculationRules;
use Koha::Database;
use Koha::Booking;
use Koha::DateUtils qw( dt_from_string output_pref );
use Koha::Exceptions::Calendar;
use Koha::Item::Availability::Checkout;
use Koha::Recall;
use Koha::Statistics;
use Koha::Token;

my $builder = t::lib::TestBuilder->new;
my $schema  = Koha::Database->new->schema;

subtest 'checkout_availability() tests' => sub {

    plan tests => 10;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );

    isa_ok( $result, 'Koha::Item::Availability::Checkout::Result', 'Returns a checkout result' );
    isa_ok( $result, 'Koha::Result::Availability' );
    ok( $result->available,           'Item is available for checkout' );
    ok( !$result->needs_confirmation, 'No confirmation needed' );
    is( $result->context->{item}->id,   $item->id,   'item context set' );
    is( $result->context->{patron}->id, $patron->id, 'patron context set' );
    is( $result->context->{user}->id,   $user->id,   'user context set' );

    $result = $item->checkout_availability( { patron => $patron, interface => 'opac' } );
    is( $result->context->{user}->id, $patron->id, 'user defaults to the patron for the opac interface' );

    throws_ok { $item->checkout_availability( {} ) }
    'Koha::Exceptions::MissingParameter', 'patron is mandatory';

    throws_ok { $item->checkout_availability( { patron => $patron, interface => 'sip' } ) }
    'Koha::Exceptions::BadParameter', 'Only intranet and opac interfaces are accepted';

    $schema->storage->txn_rollback;
};

subtest 'key mapping tests' => sub {

    plan tests => 53;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride', 1 );

    my $recall       = Koha::Recall->new( { recall_id => 5 } );
    my $booking      = Koha::Booking->new( { booking_id => 6 } );
    my $next_booking = Koha::Booking->new( { booking_id => 7 } );
    my $due_date     = dt_from_string('2020-01-01T10:00:00');

    my $impossible = {
        GNA                             => 1,
        CARD_LOST                       => 1,
        DEBARRED                        => 1,
        EXPIRED                         => 1,
        USERBLOCKEDWITHENDDATE          => '2099-01-01',
        DEBT_GUARANTORS                 => 12,
        DEBT_LINKED_ACCOUNTS            => 13,
        TOO_MANY                        => 'TOO_MANY_CHECKOUTS',
        current_loan_count              =>  3,
        max_loans_allowed               =>  2,
        NOT_FOR_LOAN                    =>  1,
        item_notforloan                 => -1,
        WTHDRAWN                        =>  1,
        RESTRICTED                      =>  1,
        ITEMNOTSAMEBRANCH               =>  1,
        itemhomebranch                  => 'HOME',
        RETURN_IMPOSSIBLE               => 1,
        branch_to_return                => 'RETURN',
        NO_MORE_RENEWALS                => 1,
        NO_RENEWAL_FOR_ONSITE_CHECKOUTS => 1,
        RECALLED_INTRANSIT              => 'PICKUP',
        AGE_RESTRICTION                 => 'PEGI 18',
        USERBLOCKEDOVERDUE              => 2,
        UNKNOWN_BARCODE                 => 1,
    };
    my $confirmation = {
        DEBT                         => 10,
        DEBT_GUARANTEES              => 11,
        circulation_rule_TOO_MANY    => { rule_name => 'maxissueqty' },
        PATRON_CANT                  => 1,
        circulation_rule_PATRON_CANT => { rule_name => 'maxissueqty' },
        ISSUED_TO_ANOTHER            => 1,
        issued_borrowernumber        => 42,
        issued_firstname             => 'Jane',
        issued_surname               => 'Doe',
        issued_cardnumber            => 'CARD42',
        RESERVE_WAITING              => 1,
        resborrowernumber            => 43,
        resfirstname                 => 'John',
        ressurname                   => 'Smith',
        rescardnumber                => 'CARD43',
        resbranchcode                => 'PICKUP',
        reswaitingdate               => '2026-01-02',
        reserve_id                   => 99,
        RENEW_ISSUE                  => 1,
        CURRENTISSUE                 => 1,
        PREVISSUE                    => 1,
        ITEM_LOST                    => 'Lost',
        BORRNOTSAMEBRANCH            => 'PATRONLIB',
        RENTALCHARGE                 => 5,
        RECALLED                     => $recall,
        BOOKED_EARLY                 => $booking,
        BOOKED_TO_ANOTHER            => $booking,
        BOOKED_DUE_DATE_CLASH        => $next_booking,
        HIGHHOLDS                    => { num_holds => 5, duration => 7, returndate => $due_date },
        BIBLIO_ALREADY_ISSUED        => 1,
        ADDITIONAL_MATERIALS         => 'A CD',
        INVALID_DATE                 => $due_date,
        SUPPLY_ILL                   => 1,
        iso18626_payload_supplyill   => 7,
        NOT_FOR_LOAN_FORCING         => 1,
        itemtype_notforloan          => 'BK',
    };
    my $alerts = {
        OTHER_CHARGES              => '1.00',
        ITEM_LOST                  => 'Lost',
        HIGHHOLDS                  => { num_holds  => 5 },
        RETURNED_FROM_ANOTHER      => { patron     => $user },
        LINKED_ACCOUNT_HOLD_PICKUP => { reserve_id => 1, hold_patron_id => 2, hold_patron => $user },
        BOOKED                     => $booking,
    };
    my $messages = {
        ONSITE_CHECKOUT_WILL_BE_SWITCHED => 1,
        RECALLED                         => 3,
    };

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock( 'CanBookBeIssued', sub { return ( $impossible, $confirmation, $alerts, $messages ) } );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    my $b      = $result->blockers;
    my $c      = $result->confirmations;
    my $w      = $result->warnings;

    is_deeply(
        [ sort keys %{$b} ],
        [
            qw( age_restriction card_lost debt_guarantors debt_linked_accounts gone_no_address item_not_same_branch
                item_restricted no_more_renewals no_renewal_for_onsite_checkouts not_for_loan patron_debarred
                patron_debarred_until patron_expired patron_has_overdues recalled_in_transit return_impossible
                too_many unknown_barcode withdrawn )
        ],
        'Blocker keys mapped, data keys folded'
    );
    is_deeply(
        [ sort keys %{$c} ],
        [
            qw( additional_materials biblio_already_issued booked_due_date_clash booked_early booked_to_another
                current_checkout debt debt_guarantees high_holds invalid_date issued_to_another item_lost
                not_for_loan_forcing patron_cant patron_not_same_branch previous_checkout recalled renew_issue
                rental_charge reserve_waiting supply_ill )
        ],
        'Confirmation keys mapped, data keys folded'
    );
    is_deeply(
        [ sort keys %{$w} ],
        [
            qw( booked high_holds item_lost linked_account_hold_pickup onsite_checkout_will_be_switched
                other_charges recall_for_patron returned_from_another )
        ],
        'Warning keys mapped'
    );

    # Blocker payloads
    is( $b->{gone_no_address},       1,            'gone_no_address' );
    is( $b->{card_lost},             1,            'card_lost' );
    is( $b->{patron_debarred},       1,            'patron_debarred' );
    is( $b->{patron_expired},        1,            'patron_expired' );
    is( $b->{patron_debarred_until}, '2099-01-01', 'patron_debarred_until carries the end date' );
    is( $b->{debt_guarantors},       12,           'debt_guarantors carries the amount' );
    is( $b->{debt_linked_accounts},  13,           'debt_linked_accounts carries the amount' );
    is_deeply(
        $b->{too_many},
        {
            reason           => 'TOO_MANY_CHECKOUTS', count => 3, max_allowed => 2,
            circulation_rule => { rule_name => 'maxissueqty' }
        },
        'too_many folds counts and the circulation rule, even from the confirmations hash'
    );
    is_deeply( $b->{not_for_loan},         { notforloan => -1 },       'not_for_loan carries the item status' );
    is_deeply( $b->{item_not_same_branch}, { library_id => 'HOME' },   'item_not_same_branch' );
    is_deeply( $b->{return_impossible},    { library_id => 'RETURN' }, 'return_impossible' );
    is( $b->{withdrawn},                       1,         'withdrawn' );
    is( $b->{item_restricted},                 1,         'item_restricted' );
    is( $b->{no_more_renewals},                1,         'no_more_renewals' );
    is( $b->{no_renewal_for_onsite_checkouts}, 1,         'no_renewal_for_onsite_checkouts' );
    is( $b->{recalled_in_transit},             'PICKUP',  'recalled_in_transit' );
    is( $b->{age_restriction},                 'PEGI 18', 'age_restriction' );
    is( $b->{patron_has_overdues},             2,         'patron_has_overdues' );

    # Confirmation payloads
    is( $c->{debt},            10, 'debt' );
    is( $c->{debt_guarantees}, 11, 'debt_guarantees' );
    is_deeply( $c->{patron_cant}, { circulation_rule => { rule_name => 'maxissueqty' } }, 'patron_cant' );
    is_deeply(
        $c->{issued_to_another},
        { patron_id => 42, firstname => 'Jane', surname => 'Doe', cardnumber => 'CARD42' },
        'issued_to_another folds the borrower'
    );
    is_deeply(
        $c->{reserve_waiting},
        {
            hold_id           => 99, patron_id => 43, firstname => 'John', surname => 'Smith', cardnumber => 'CARD43',
            pickup_library_id => 'PICKUP', hold_date => undef, waiting_date => '2026-01-02'
        },
        'reserve_waiting folds the hold'
    );
    is( $c->{renew_issue},            1,           'renew_issue' );
    is( $c->{current_checkout},       1,           'current_checkout' );
    is( $c->{previous_checkout},      1,           'previous_checkout' );
    is( $c->{item_lost},              'Lost',      'item_lost' );
    is( $c->{patron_not_same_branch}, 'PATRONLIB', 'patron_not_same_branch' );
    is( $c->{rental_charge},          5,           'rental_charge' );
    is_deeply( $c->{recalled},              { recall_id  => 5 }, 'recalled carries the recall id' );
    is_deeply( $c->{booked_early},          { booking_id => 6 }, 'booked_early carries the booking id' );
    is_deeply( $c->{booked_to_another},     { booking_id => 6 }, 'booked_to_another carries the booking id' );
    is_deeply( $c->{booked_due_date_clash}, { booking_id => 7 }, 'booked_due_date_clash carries the booking id' );
    is_deeply(
        $c->{high_holds},
        { num_holds => 5, duration => 7, returndate => output_pref( { dt => $due_date, dateformat => 'rfc3339' } ) },
        'high_holds carries the return date as RFC3339'
    );
    is( $c->{biblio_already_issued}, 1,      'biblio_already_issued' );
    is( $c->{additional_materials},  'A CD', 'additional_materials' );
    is_deeply(
        $c->{invalid_date}, { due_date => output_pref( { dt => $due_date, dateformat => 'rfc3339' } ) },
        'invalid_date carries the due date as RFC3339'
    );
    is_deeply( $c->{supply_ill},           { iso18626_request_id => 7 },    'supply_ill' );
    is_deeply( $c->{not_for_loan_forcing}, { itemtype            => 'BK' }, 'not_for_loan_forcing (item type)' );

    # Warnings
    is( $w->{other_charges},                    '1.00', 'other_charges' );
    is( $w->{onsite_checkout_will_be_switched}, 1,      'onsite_checkout_will_be_switched' );
    is( $w->{recall_for_patron},                3,      'RECALLED message is recall_for_patron' );
    is_deeply( $w->{returned_from_another}, { patron_id => $user->id }, 'returned_from_another' );
    is_deeply(
        $w->{linked_account_hold_pickup}, { hold_id => 1, patron_id => 2 },
        'linked_account_hold_pickup carries ids'
    );
    is_deeply( $w->{booked}, { booking_id => 6 }, 'booked carries the booking id' );

    # Both ways
    my $map = Koha::Item::Availability::Checkout::KEY_MAP;
    is(
        scalar( grep { Koha::Item::Availability::Checkout->key_from_legacy($_) eq $map->{$_} } keys %{$map} ),
        scalar keys %{$map}, 'key_from_legacy maps every legacy key'
    );
    is(
        scalar( grep { Koha::Item::Availability::Checkout->legacy_from_key( $map->{$_} ) eq $_ } keys %{$map} ),
        scalar keys %{$map}, 'legacy_from_key maps every key back'
    );
    my %values;
    $values{$_}++ for values %{$map};
    is( scalar( grep { $values{$_} > 1 } keys %values ),                      0, 'The mapping is one to one' );
    is( Koha::Item::Availability::Checkout->key_from_legacy('SOMETHING_NEW'), 'something_new', 'Unknown legacy key' );
    is( Koha::Item::Availability::Checkout->legacy_from_key('something_new'), 'SOMETHING_NEW', 'Unknown key' );

    $schema->storage->txn_rollback;
};

subtest 'patron status tests' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    $patron->set( { gonenoaddress => 1, lost => 1 } )->store;
    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{gone_no_address}, 1, 'gone_no_address' );
    is( $result->blockers->{card_lost},       1, 'card_lost' );

    $patron->set( { gonenoaddress => 0, lost => 0, dateexpiry => '2000-01-01' } )->store;
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{patron_expired}, 1, 'patron_expired' );

    $patron->set( { dateexpiry => dt_from_string->add( years => 1 ), debarred => '9999-12-31' } )->store;
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{patron_debarred},              1,            'patron_debarred' );
    is( $result->blockers->{patron_debarred_indefinitely}, '9999-12-31', 'patron_debarred_indefinitely' );

    my $until = dt_from_string->add( days => 10 )->ymd;
    $patron->set( { debarred => $until } )->store;
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{patron_debarred_until}, $until, 'patron_debarred_until' );

    $patron->set( { debarred => undef } )->store;
    ok( $item->checkout_availability( { patron => $patron, user => $user } )->available, 'Available again' );

    $schema->storage->txn_rollback;
};

subtest 'debt tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    t::lib::Mocks::mock_preference( 'noissuescharge',       5 );
    t::lib::Mocks::mock_preference( 'AllowFineOverride',    0 );
    t::lib::Mocks::mock_preference( 'AllFinesNeedOverride', 0 );

    $patron->account->add_debit( { amount => 10, type => 'OVERDUE', interface => 'test' } );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{debt} + 0, 10, 'debt blocker carries the amount' );

    t::lib::Mocks::mock_preference( 'AllowFineOverride', 1 );
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->confirmations->{debt} + 0, 10, 'debt confirmation with AllowFineOverride' );
    ok( $result->available, 'no blockers' );

    $schema->storage->txn_rollback;
};

subtest 'item status tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    t::lib::Mocks::mock_preference( 'AllowNotForLoanOverride', 0 );
    $item->set( { withdrawn => 1, restricted => 1, notforloan => 2 } )->store;

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{withdrawn},       1, 'withdrawn' );
    is( $result->blockers->{item_restricted}, 1, 'item_restricted' );
    is_deeply( $result->blockers->{not_for_loan}, { notforloan => 2 }, 'not_for_loan' );

    t::lib::Mocks::mock_preference( 'AllowNotForLoanOverride', 1 );
    $item->set( { withdrawn => 0, restricted => 0 } )->store;
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply( $result->confirmations->{not_for_loan_forcing}, { notforloan => 2 }, 'not_for_loan_forcing' );

    my $lost = $builder->build_object(
        { class => 'Koha::AuthorisedValues', value => { category => 'LOST', authorised_value => 7, lib => 'Gone' } } );
    $item->set( { notforloan => 0, itemlost => 7 } )->store;
    t::lib::Mocks::mock_preference( 'IssueLostItem', 'confirm' );
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->confirmations->{item_lost}, 'Gone', 'item_lost confirmation' );

    t::lib::Mocks::mock_preference( 'IssueLostItem', 'alert' );
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->warnings->{item_lost}, 'Gone', 'item_lost warning' );
    ok( !$result->needs_confirmation, 'no confirmation for an alert' );

    t::lib::Mocks::mock_preference( 'CircConfirmItemParts', 1 );
    $item->set( { itemlost => 0, materials => 'A CD' } )->store;
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->confirmations->{additional_materials}, 'A CD', 'additional_materials' );
    ok( $result->available, 'no blockers' );

    $schema->storage->txn_rollback;
};

subtest 'checkouts tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $other_patron = build_patron();

    t::lib::Mocks::mock_preference( 'AutoReturnCheckedOutItems', 0 );
    $builder->build_object(
        {
            class => 'Koha::Checkouts',
            value => { itemnumber => $item->id, borrowernumber => $other_patron->id, branchcode => $item->homebranch }
        }
    );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply(
        $result->confirmations->{issued_to_another},
        {
            patron_id => $other_patron->id,      firstname  => $other_patron->firstname,
            surname   => $other_patron->surname, cardnumber => $other_patron->cardnumber
        },
        'issued_to_another carries the current borrower'
    );

    t::lib::Mocks::mock_preference( 'AutoReturnCheckedOutItems', 1 );
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->warnings->{returned_from_another}->{patron_id}, $other_patron->id, 'returned_from_another' );

    t::lib::Mocks::mock_preference( 'AllowMultipleIssuesOnABiblio', 0 );
    my $other_item = $builder->build_sample_item( { biblionumber => $item->biblionumber, itype => $item->itype } );
    $result = $other_item->checkout_availability( { patron => $other_patron, user => $user } );
    is( $result->confirmations->{biblio_already_issued}, 1, 'biblio_already_issued' );

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock( 'CanBookBeRenewed', sub { return ( 1, undef ) } );
    $result = $item->checkout_availability( { patron => $other_patron, user => $user } );
    is( $result->confirmations->{renew_issue}, 1, 'renew_issue' );

    $schema->storage->txn_rollback;
};

subtest 'holds and AllowHoldCheckoutOverride tests' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $hold_patron = build_patron();

    my $restype  = 'Reserved';
    my $reserves = Test::MockModule->new('C4::Reserves');
    $reserves->mock(
        'CheckReserves',
        sub {
            return (
                $restype,
                {
                    borrowernumber => $hold_patron->id, branchcode  => 'PICKUP', reserve_id => 123,
                    reservedate    => '2026-01-01',     waitingdate => '2026-01-05'
                }
            );
        }
    );

    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride', 1 );
    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply(
        $result->confirmations->{reserved},
        {
            hold_id           => 123, patron_id => $hold_patron->id, firstname => $hold_patron->firstname,
            surname           => $hold_patron->surname, cardnumber => $hold_patron->cardnumber,
            pickup_library_id => 'PICKUP',              hold_date  => '2026-01-01', waiting_date => undef
        },
        'reserved confirmation carries the hold'
    );
    ok( $result->available, 'no blockers' );

    for my $type (qw( Waiting Transferred Processing )) {
        $restype = $type;
        $result  = $item->checkout_availability( { patron => $patron, user => $user } );
        my $key = { Waiting => 'reserve_waiting', Transferred => 'transferred', Processing => 'processing' }->{$type};
        ok( $result->confirmations->{$key}, "$key confirmation" );
    }

    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride', 0 );
    $restype = 'Reserved';
    $result  = $item->checkout_availability( { patron => $patron, user => $user } );
    ok(
        !exists $result->confirmations->{reserved},
        'reserved is not a confirmation without AllowHoldCheckoutOverride'
    );
    is( $result->blockers->{reserved}->{hold_id}, 123, 'reserved is promoted to a blocker, keeping its payload' );

    $result = $item->checkout_availability( { patron => $patron, user => $user, ignore_reserves => 1 } );
    ok( $result->available, 'ignore_reserves skips the holds check' );

    $schema->storage->txn_rollback;
};

subtest 'OnSiteCheckoutsForce tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    $item->set( { withdrawn => 1 } )->store;
    t::lib::Mocks::mock_preference( 'CircConfirmItemParts', 1 );
    $item->set( { materials => 'A CD' } )->store;

    t::lib::Mocks::mock_preference( 'OnSiteCheckoutsForce', 1 );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is( $result->blockers->{withdrawn}, 1, 'Not relaxed for regular checkouts' );

    $result = $item->checkout_availability( { patron => $patron, user => $user, onsite_checkout => 1 } );
    ok( $result->available, 'Blockers relaxed for on-site checkouts' );
    is( $result->warnings->{withdrawn}, 1, 'The relaxed blocker is a warning' );
    is_deeply( $result->forced, { withdrawn => 1 }, 'The relaxed blocker is recorded as forced' );
    is( $result->confirmations->{additional_materials}, 'A CD', 'Confirmations are not relaxed' );
    is_deeply(
        $result->legacy_override_params,
        { confirmations => ['ADDITIONAL_MATERIALS'], forced => ['WTHDRAWN'] },
        'legacy_override_params reports the forced keys'
    );

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock(
        'CanBookBeIssued',
        sub { return ( { BOOKED_TO_ANOTHER => Koha::Booking->new( { booking_id => 1 } ), WTHDRAWN => 1 }, {}, {}, {} ) }
    );
    $result = $item->checkout_availability( { patron => $patron, user => $user, onsite_checkout => 1 } );
    is_deeply( [ keys %{ $result->blockers } ], ['booked_to_another'], 'booked_to_another is never relaxed' );

    t::lib::Mocks::mock_preference( 'OnSiteCheckoutsForce', 0 );
    $result = $item->checkout_availability( { patron => $patron, user => $user, onsite_checkout => 1 } );
    is( $result->blockers->{withdrawn}, 1, 'Not relaxed without OnSiteCheckoutsForce' );
    is_deeply( $result->forced, {}, 'Nothing forced' );

    $schema->storage->txn_rollback;
};

subtest 'force_checkout permission tests' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $no_perms = build_patron( { flags => 0 } );

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock(
        'CanBookBeIssued',
        sub {
            return (
                {},
                { DEBT => 10, HIGHHOLDS => { num_holds => 5 }, ADDITIONAL_MATERIALS => 'A CD', RENEW_ISSUE => 1 }, {},
                {}
            );
        }
    );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    ok( $result->available, 'User with force_checkout: no blockers' );
    is_deeply(
        [ sort keys %{ $result->confirmations } ], [qw( additional_materials debt high_holds renew_issue )],
        'User with force_checkout: all confirmations kept'
    );

    $result = $item->checkout_availability( { patron => $patron, user => $no_perms } );
    ok( !$result->available, 'User without force_checkout: blocked' );
    is_deeply(
        [ sort keys %{ $result->blockers } ], [qw( debt renew_issue )],
        'Confirmations requiring force_checkout are promoted'
    );
    is( $result->blockers->{debt}, 10, 'Payload kept' );
    is_deeply(
        [ sort keys %{ $result->confirmations } ], [qw( additional_materials high_holds )],
        'high_holds and additional_materials do not require force_checkout'
    );

    $result = $item->checkout_availability( { patron => $patron } );
    is_deeply( [ sort keys %{ $result->blockers } ], [qw( debt renew_issue )], 'No user: treated as no permission' );

    $result = $item->checkout_availability( { patron => $patron, user => $no_perms, interface => 'opac' } );
    ok( exists $result->confirmations->{debt}, 'The permission rule does not apply to the opac interface' );

    $schema->storage->txn_rollback;
};

subtest 'opac interface tests' => sub {

    plan tests => 13;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    my $booking = $builder->build_object( { class => 'Koha::Bookings' } );
    my $confirmation;
    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock(
        'CanBookBeIssued',
        sub {
            return (
                { NOT_FOR_LOAN => 1, item_notforloan => 2 },
                {%$confirmation},
                { RETURNED_FROM_ANOTHER => { patron => $patron } },
                {}
            );
        }
    );

    $confirmation = {
        TOO_MANY              => 'TOO_MANY_CHECKOUTS', current_loan_count    => 3,  max_loans_allowed => 2,
        ISSUED_TO_ANOTHER     => 1,                    issued_borrowernumber => 42, issued_surname    => 'Doe',
        AGE_RESTRICTION       => 'PEGI 18',
        RESERVED              => 1, resborrowernumber => 43, resfirstname => 'John',
        RECALLED              => Koha::Recall->new( { recall_id => 5 } ),
        BOOKED_DUE_DATE_CLASH => $booking,
        DEBT                  => 10,
    };

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 0 );
    my $result = $item->checkout_availability( { patron => $patron, interface => 'opac' } );
    is_deeply(
        [ sort keys %{ $result->blockers } ],
        [qw( age_restriction issued_to_another not_for_loan reserved too_many )],
        'Public promotions'
    );
    is_deeply( $result->blockers->{too_many}->{count}, 3, 'too_many keeps the counts' );
    is( $result->blockers->{issued_to_another}, 1, 'issued_to_another is stripped' );
    is( $result->blockers->{reserved},          1, 'reserved is stripped' );
    is_deeply( $result->blockers->{not_for_loan}, {}, 'not_for_loan loses the item status' );
    is( $result->confirmations->{recalled},              1,  'recalled is stripped' );
    is( $result->confirmations->{booked_due_date_clash}, 1,  'booked_due_date_clash is stripped' );
    is( $result->confirmations->{debt},                  10, 'other confirmations remain' );
    is( $result->warnings->{returned_from_another},      1,  'returned_from_another is stripped' );

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 1 );
    $result = $item->checkout_availability( { patron => $patron, interface => 'opac' } );
    ok(
        !exists $result->blockers->{reserved} && !exists $result->confirmations->{reserved},
        'AllowItemsOnHoldCheckoutSCO=1: pending holds allowed and dropped'
    );

    $confirmation = { RESERVE_WAITING => 1, resborrowernumber => 43 };
    $result       = $item->checkout_availability( { patron => $patron, interface => 'opac' } );
    is( $result->blockers->{reserve_waiting}, 1, 'AllowItemsOnHoldCheckoutSCO=1: waiting holds blocked' );

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 2 );
    $result = $item->checkout_availability( { patron => $patron, interface => 'opac' } );
    ok( !exists $result->blockers->{reserve_waiting},      'AllowItemsOnHoldCheckoutSCO=2: waiting holds allowed' );
    ok( !exists $result->confirmations->{reserve_waiting}, 'AllowItemsOnHoldCheckoutSCO=2: and dropped' );

    $schema->storage->txn_rollback;
};

subtest 'dates tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    my $past   = dt_from_string->subtract( days => 2 );
    my $result = $item->checkout_availability( { patron => $patron, user => $user, due_date => $past } );
    is(
        $result->confirmations->{invalid_date}->{due_date},
        output_pref( { dt => $past, dateformat => 'rfc3339' } ),
        'invalid_date carries the due date'
    );

    $result = $item->checkout_availability( { patron => $patron, user => $user, due_date => $past->ymd } );
    ok( $result->confirmations->{invalid_date}, 'due_date accepts strings' );

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock( 'CalcDateDue', sub { Koha::Exceptions::Calendar::NoOpenDays->throw } );
    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply( $result->blockers, { no_open_days => 1 }, 'no_open_days' );

    $c4_circ->mock( 'CalcDateDue', sub { Koha::Exception->throw('Boom') } );
    throws_ok { $item->checkout_availability( { patron => $patron, user => $user } ) }
    'Koha::Exception', 'Other exceptions are rethrown';

    $schema->storage->txn_rollback;
};

subtest 'no side effects tests' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    t::lib::Mocks::mock_preference( 'IssueLog', 1 );

    my $statistical = build_patron( { category_type => 'X' } );
    my $last_seen   = $item->datelastseen;

    my $stats_count = Koha::Statistics->search->count;
    my $logs_count  = Koha::ActionLogs->search->count;

    my $result = $item->checkout_availability( { patron => $statistical, user => $user } );

    is_deeply( $result->blockers, { statistical_patron => 1 }, 'statistical_patron blocker' );
    is( Koha::Statistics->search->count,       $stats_count,    'No statistic recorded for a statistical patron' );
    is( $item->get_from_storage->datelastseen, $last_seen,      'datelastseen untouched' );
    is( $item->get_from_storage->localuse,     $item->localuse, 'localuse untouched' );

    $result = $item->checkout_availability( { patron => $patron, user => $user } );
    ok( $result->available, 'Regular patron can check out' );
    is( Koha::Statistics->search->count, $stats_count, 'No statistic recorded' );
    is( Koha::ActionLogs->search->count, $logs_count,  'No action log recorded' );

    $schema->storage->txn_rollback;
};

subtest 'token binding tests' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $other_patron = build_patron();
    my $other_user   = build_patron( { flags => 1 } );

    t::lib::Mocks::mock_preference( 'CircConfirmItemParts', 1 );
    $item->set( { materials => 'A CD' } )->store;

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    ok( $result->needs_confirmation, 'Confirmation needed' );
    is_deeply( $result->token_params, [qw( item patron user )], 'Token bound to item, patron and user' );

    my $token = $result->as_token;
    ok( $item->checkout_availability( { patron => $patron, user => $user } )->check_token($token), 'Token is valid' );
    ok(
        !$item->checkout_availability( { patron => $other_patron, user => $user } )->check_token($token),
        'Token for patron A is not valid for patron B'
    );
    ok(
        !$item->checkout_availability( { patron => $patron, user => $other_user } )->check_token($token),
        'Token is not valid for another user'
    );

    my $expired = Koha::Token->new->generate_jwt( { id => $result->_token_id, expires => time - 10 } );
    ok( !$result->check_token($expired), 'Expired tokens are rejected' );

    ok( $result->to_api->{confirmation_token}, 'to_api includes a token' );

    $schema->storage->txn_rollback;
};

subtest 'legacy_override_params() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply( $result->legacy_override_params, { confirmations => [], forced => [] }, 'Empty' );

    $result->add_confirmation( previous_checkout => 1 );
    $result->add_confirmation( debt              => 1 );
    $result->add_blocker( patron_debarred => 1 );
    is_deeply(
        $result->legacy_override_params,
        { confirmations => [qw( DEBT PREVISSUE )], forced => ['DEBARRED'] },
        'Legacy UPPERCASE keys'
    );

    $schema->storage->txn_rollback;
};

subtest 'promote_confirmation() and relax_blocker() tests' => sub {

    plan tests => 6;

    my $result = Koha::Item::Availability::Checkout::Result->new;
    $result->add_confirmation( debt => 10 );
    $result->add_blocker( withdrawn => 1 );

    $result->promote_confirmation('debt');
    is( $result->blockers->{debt}, 10, 'Promoted with its payload' );
    ok( !exists $result->confirmations->{debt}, 'No longer a confirmation' );
    $result->promote_confirmation('nothing');
    ok( !exists $result->blockers->{nothing}, 'Promoting a missing key is a no-op' );

    $result->relax_blocker('withdrawn');
    ok( !exists $result->blockers->{withdrawn}, 'No longer a blocker' );
    is( $result->warnings->{withdrawn}, 1, 'Now a warning' );
    is( $result->forced->{withdrawn},   1, 'Recorded as forced' );
};

subtest 'overrides tests' => sub {

    plan tests => 13;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $no_perms = build_patron( { flags => 0 } );

    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock(
        'CanBookBeIssued',
        sub { return ( { DEBARRED => 1, WTHDRAWN => 1, UNKNOWN_BARCODE => 1 }, { DEBT => 10 }, {}, {} ) }
    );

    my $result = $item->checkout_availability( { patron => $patron, user => $user } );
    is_deeply(
        [ sort keys %{ $result->blockers } ], [qw( patron_debarred unknown_barcode withdrawn )],
        'Nothing overridden without overrides'
    );

    $result = $item->checkout_availability(
        { patron => $patron, user => $user, overrides => { patron_debarred => 1, unknown_barcode => 1 } } );
    is_deeply(
        [ sort keys %{ $result->blockers } ], [qw( unknown_barcode withdrawn )],
        'Only the listed blockers are overridden, unknown_barcode never is'
    );
    is( $result->warnings->{patron_debarred}, 1, 'Overridden blockers are reported as warnings' );

    $result = $item->checkout_availability( { patron => $patron, user => $user, overrides => { any => 1 } } );
    is_deeply( [ keys %{ $result->blockers } ], ['unknown_barcode'], 'any: all overridable blockers overridden' );
    is_deeply(
        [ sort keys %{ $result->forced } ], [qw( patron_debarred withdrawn )],
        'Overridden blockers are recorded as forced'
    );
    is_deeply( $result->to_api->{forced}, [qw( patron_debarred withdrawn )], 'to_api lists the forced keys' );
    is_deeply( [ keys %{ $result->confirmations } ], ['debt'],               'Confirmations are not affected' );
    is_deeply(
        $result->legacy_override_params,
        { confirmations => ['DEBT'], forced => [qw( DEBARRED UNKNOWN_BARCODE WTHDRAWN )] },
        'Overridden keys are reported as forced to AddIssue'
    );

    $result = $item->checkout_availability( { patron => $patron, user => $no_perms, overrides => { any => 1 } } );
    is_deeply(
        [ sort keys %{ $result->blockers } ], [qw( debt patron_debarred unknown_barcode withdrawn )],
        'User without force_checkout: nothing overridden'
    );

    $result = $item->checkout_availability(
        { patron => $patron, user => $user, overrides => { any => 1 }, interface => 'opac' } );
    ok( exists $result->blockers->{patron_debarred}, 'Overrides do not apply to the opac interface' );

    $c4_circ->mock( 'CanBookBeIssued', sub { return ( {}, { DEBT => 10 }, {}, {} ) } );
    $result = $item->checkout_availability( { patron => $patron, user => $user, overrides => { any => 1 } } );
    is_deeply( $result->to_api->{forced}, [], 'Nothing forced when there are no blockers' );

    $c4_circ->mock( 'CanBookBeIssued', sub { return ( {}, { RESERVED => 1, reserve_id => 1 }, {}, {} ) } );
    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride', 0 );
    $result =
        $item->checkout_availability( { patron => $patron, user => $user, overrides => { any => 1, reserved => 1 } } );
    ok( exists $result->blockers->{reserved}, 'AllowHoldCheckoutOverride disabled: holds are not overridden' );

    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride', 1 );
    $result = $item->checkout_availability( { patron => $patron, user => $user, overrides => { any => 1 } } );
    ok( exists $result->confirmations->{reserved}, 'AllowHoldCheckoutOverride enabled: holds are confirmations' );

    $schema->storage->txn_rollback;
};

subtest 'library tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    my ( $patron, $user, $item ) = setup();
    my $library         = $builder->build_object( { class => 'Koha::Libraries' } );
    my $userenv_library = C4::Context->userenv->{branch};

    my $library_seen;
    my $c4_circ = Test::MockModule->new('C4::Circulation');
    $c4_circ->mock(
        'CanBookBeIssued',
        sub { $library_seen = C4::Context->userenv->{branch}; return ( {}, {}, {}, {} ) }
    );

    $item->checkout_availability( { patron => $patron, user => $user } );
    is( $library_seen, $userenv_library, 'Defaults to the user environment library' );

    $item->checkout_availability( { patron => $patron, user => $user, library => $library->branchcode } );
    is( $library_seen,                  $library->branchcode, 'The library parameter is used for the check' );
    is( C4::Context->userenv->{branch}, $userenv_library,     'The user environment is restored' );

    $schema->storage->txn_rollback;
};

sub build_patron {
    my ($params) = @_;

    my $category = $builder->build_object(
        {
            class => 'Koha::Patron::Categories',
            value => {
                category_type                          => $params->{category_type} // 'A',
                noissuescharge                         => undef,
                noissueschargeguarantees               => undef,
                noissueschargeguarantorswithguarantees => undef,
            }
        }
    );

    return $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => {
                categorycode => $category->categorycode,
                dateexpiry   => dt_from_string->add( years => 1 ),
                flags        => $params->{flags} // 0,
                dateofbirth  => undef,
            }
        }
    );
}

sub setup {

    t::lib::Mocks::mock_preference( 'item-level_itypes',              1 );
    t::lib::Mocks::mock_preference( 'AllowMultipleIssuesOnABiblio',   1 );
    t::lib::Mocks::mock_preference( 'AllowTooManyOverride',           0 );
    t::lib::Mocks::mock_preference( 'AllowHoldCheckoutOverride',      1 );
    t::lib::Mocks::mock_preference( 'CircConfirmItemParts',           0 );
    t::lib::Mocks::mock_preference( 'RentalFeesCheckoutConfirmation', 0 );
    t::lib::Mocks::mock_preference( 'decreaseLoanHighHolds',          0 );
    t::lib::Mocks::mock_preference( 'UseRecalls',                     'off' );
    t::lib::Mocks::mock_preference( 'ILLModule',                      0 );
    t::lib::Mocks::mock_preference( 'IndependentBranches',            0 );
    t::lib::Mocks::mock_preference( 'CheckPrevCheckout',              'hardno' );
    t::lib::Mocks::mock_preference( 'OverduesBlockCirc',              'noblock' );
    t::lib::Mocks::mock_preference( 'OnSiteCheckoutsForce',           0 );
    t::lib::Mocks::mock_preference( 'noissuescharge',                 undef );
    t::lib::Mocks::mock_preference( 'AllFinesNeedOverride',           0 );
    t::lib::Mocks::mock_preference( 'AllowReturnToBranch',            'anywhere' );

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = build_patron();
    my $user    = build_patron( { flags => 1 } );
    t::lib::Mocks::mock_userenv( { patron => $user, branchcode => $library->branchcode } );

    my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $item     = $builder->build_sample_item( { library => $library->branchcode, itype => $itemtype->itemtype } );

    Koha::CirculationRules->set_rules(
        {
            categorycode => undef,
            branchcode   => undef,
            itemtype     => undef,
            rules        => {
                maxissueqty       => 10,
                maxonsiteissueqty => 10,
                issuelength       => 14,
                lengthunit        => 'days',
                renewalsallowed   => 5,
            }
        }
    );

    return ( $patron, $user, $item );
}
