package Koha::REST::V1::Checkouts;

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

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;

use C4::Context;
use C4::Circulation qw( AddIssue AddRenewal CanBookBeRenewed );
use Koha::Checkouts;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
use Koha::Item::Availability::Checkout;
use Koha::Items;
use Koha::Libraries;
use Koha::Old::Checkouts;
use Koha::Patrons;
use Koha::Token;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

=head1 NAME

Koha::REST::V1::Checkout

=head1 API

=head2 Methods

=head3 list

List Koha::Checkout objects

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    my $checked_in = $c->param('checked_in');
    $c->req->params->remove('checked_in');

    try {
        my $checkouts_set;

        if ($checked_in) {
            $checkouts_set = Koha::Old::Checkouts->new;
        } else {
            $checkouts_set = Koha::Checkouts->new;
        }

        my $checkouts = $c->objects->search($checkouts_set);

        return $c->render(
            status  => 200,
            openapi => $checkouts
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

get one checkout

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->param('checkout_id');

    my $checkout = Koha::Checkouts->find($checkout_id);
    $checkout = Koha::Old::Checkouts->find($checkout_id)
        unless $checkout;

    return $c->render_resource_not_found("Checkout")
        unless $checkout;

    return try {
        return $c->render(
            status  => 200,
            openapi => $c->objects->to_api($checkout),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 _check_availability

Internal function to call CanBookBeIssued and return an appropriately filtered
set return

=cut

sub _check_availability {
    my ( $c, $patron, $item ) = @_;

    my $inprocess       = 0;                   # What does this do?
    my $ignore_reserves = 0;                   # Don't ignore reserves
    my $params          = { item => $item };

    my ( $impossible, $confirmation, $alerts, $messages ) = C4::Circulation::CanBookBeIssued(
        $patron,          undef, undef, $inprocess,
        $ignore_reserves, $params
    );

    if ( $c->stash('is_public') ) {

        # Upgrade some confirmations to blockers
        my @should_block = qw/TOO_MANY ISSUED_TO_ANOTHER AGE_RESTRICTION/;

        # Hold-related confirmations are gated by AllowItemsOnHoldCheckoutSCO:
        #   0 = block pending and waiting holds (default)
        #   1 = allow pending holds, block waiting/transit/processing holds
        #   2 = allow pending and waiting/transit/processing holds
        my $hold_pref = C4::Context->preference('AllowItemsOnHoldCheckoutSCO') || 0;
        push @should_block, 'RESERVED'                                 if $hold_pref < 1;
        push @should_block, qw/RESERVE_WAITING TRANSFERRED PROCESSING/ if $hold_pref < 2;

        for my $block (@should_block) {
            if ( exists( $confirmation->{$block} ) ) {
                $impossible->{$block} = $confirmation->{$block};
                delete $confirmation->{$block};
            }
        }

        # Drop the remaining hold confirmations so the caller does not have
        # to resolve a confirmation token for a policy we've already permitted
        for my $allowed (qw/RESERVED RESERVE_WAITING TRANSFERRED PROCESSING/) {
            delete $confirmation->{$allowed};
        }

        # Remove any non-public info that's returned by CanBookBeIssued
        my @restricted_keys =
            qw/issued_borrowernumber issued_cardnumber issued_firstname issued_surname resborrowernumber resbranchcode rescardnumber reserve_id resfirstname resreservedate reswaitingdate ressurname item_notforloan/;
        for my $key (@restricted_keys) {
            delete $confirmation->{$key};
            delete $impossible->{$key};
            delete $alerts->{$key};
            delete $messages->{$key};
        }
    }

    return ( $impossible, $confirmation, { %{$alerts}, %{$messages} } );
}

=head3 get_availability

Controller function that handles retrieval of Checkout availability

=cut

sub get_availability {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $patron = Koha::Patrons->find( $c->param('patron_id') );
        return $c->render_resource_not_found("Patron")
            unless $patron;

        my $item = Koha::Items->find( $c->param('item_id') );
        return $c->render_resource_not_found("Item")
            unless $item;

        my $library_id = $c->_checkout_library_id( $c->param('library_id'), '/query/library_id' )
            or return;

        my $availability = $c->_checkout_availability(
            {
                item    => $item,
                patron  => $patron,
                library => $library_id,
            }
        );

        return $c->render(
            status  => 200,
            openapi => $availability->to_api,
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

Add a new checkout

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    my $body      = $c->req->json;
    my $item_id   = $body->{item_id};
    my $patron_id = $body->{patron_id};
    my $barcode   = $body->{external_id};

    return try {

        unless ( $item_id or $barcode ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => 'Missing or wrong parameters',
                    error_code => 'MISSING_OR_WRONG_PARAMETERS',
                }
            );
        }

        my $library_id = $c->_checkout_library_id( $body->{library_id}, '/body/library_id' )
            or return;

        my $item;
        if ($item_id) {
            $item = Koha::Items->find($item_id);
        } else {
            $item = Koha::Items->find( { barcode => $barcode } );
        }

        return $c->render_resource_not_found("Item")
            unless $item;

        # check that item matches when barcode and item_id were given
        if (    $item_id
            and $barcode
            and ( $item->barcode ne $barcode or $item->id != $item_id ) )
        {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'Item id and external id belong to different items',
                    error_code => 'ITEM_ID_NOT_MATCHING_EXTERNAL_ID',
                }
            );
        }

        my $patron = Koha::Patrons->find($patron_id);
        return $c->render_resource_not_found("Patron")
            unless $patron;

        my $availability = $c->_checkout_availability(
            {
                item    => $item,
                patron  => $patron,
                library => $library_id,
            }
        );

        if ( !$availability->available ) {
            return $c->render(
                status  => 403,
                openapi => {
                    error      => 'Checkout blocked',
                    error_code => 'checkout_blocked',
                    blockers   => $availability->blockers,
                }
            );
        }

        if ( $availability->needs_confirmation ) {

            my $token = $c->param('confirmation');

            unless ( $token && $availability->check_token($token) ) {
                return $c->render(
                    status  => 412,
                    openapi => {
                        error      => 'Confirmation required',
                        error_code => 'confirmation_required',
                        %{ $availability->to_api },
                    }
                );
            }
        }

        my $overrides = $availability->legacy_override_params;

        # AddIssue reads the library from the user environment
        my $userenv = C4::Context->userenv;
        local $userenv->{branch} = $library_id;

        my $checkout = Koha::Database->new->schema->txn_do(
            sub {
                return AddIssue(
                    $patron,
                    $item->barcode,
                    undef, undef, undef, undef,
                    {
                        confirmations => $overrides->{confirmations},
                        forced        => $overrides->{forced},
                    }
                );
            }
        );

        unless ($checkout) {
            return $c->render(
                status  => 500,
                openapi => { error => 'Unknown error during checkout' }
            );
        }

        # The query string is left out, as it carries the confirmation token
        $c->res->headers->location( $c->req->url->path->to_string . '/' . $checkout->id );

        return $c->render(
            status  => 201,
            openapi => $c->objects->to_api($checkout),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 public_get_availability

Controller function that handles retrieval of Checkout availability for the
public route (I<OpacTrustedCheckout>)

=cut

sub public_get_availability {
    my $c    = shift->openapi->valid_input or return;
    my $user = $c->stash('koha.user');

    my $patron_id = $c->param('patron_id');

    return if try {
        $c->auth->public($patron_id) if $c->stash('is_public');
        return 0;    # authorization successful, do not "return" after try-catch
    } catch {
        return $c->unhandled_exception($_);
    };

    my $patron = Koha::Patrons->find($patron_id);
    my $item   = Koha::Items->find( $c->param('item_id') );

    my ( $impossible, $confirmation, $warnings ) = $c->_check_availability( $patron, $item );

    my @confirm_keys = sort keys %{$confirmation};
    unshift @confirm_keys, $item->id;
    unshift @confirm_keys, $user->id
        if $user;

    my $token = Koha::Token->new->generate_jwt( { id => join( ':', @confirm_keys ) } );

    my $response = {
        blockers           => $impossible,
        confirms           => $confirmation,
        warnings           => $warnings,
        confirmation_token => $token
    };

    return $c->render( status => 200, openapi => $response );
}

=head3 public_add

Add a new checkout, public route (I<OpacTrustedCheckout>)

=cut

sub public_add {
    my $c    = shift->openapi->valid_input or return;
    my $user = $c->stash('koha.user');

    my $body      = $c->req->json;
    my $item_id   = $body->{item_id};
    my $patron_id = $body->{patron_id};
    my $onsite    = $body->{onsite_checkout};
    my $barcode   = $body->{external_id};

    return try {

        unless ( $item_id or $barcode ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => 'Missing or wrong parameters',
                    error_code => 'MISSING_OR_WRONG_PARAMETERS',
                }
            );
        }

        if ( $c->stash('is_public') ) {
            $c->auth->public($patron_id);

            return $c->render(
                status  => 405,
                openapi => {
                    error      => 'Feature disabled',
                    error_code => 'FEATURE_DISABLED'
                }
            ) if !C4::Context->preference('OpacTrustedCheckout');
        }

        my $item;
        if ($item_id) {
            $item = Koha::Items->find($item_id);
        } else {
            $item = Koha::Items->find( { barcode => $barcode } );
        }

        unless ($item) {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'Item not found',
                    error_code => 'ITEM_NOT_FOUND',
                }
            );
        }

        # check that item matches when barcode and item_id were given
        if (    $item_id
            and $barcode
            and ( $item->barcode ne $barcode or $item->id != $item_id ) )
        {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'Item id and external id belong to different items',
                    error_code => 'ITEM_ID_NOT_MATCHING_EXTERNAL_ID',
                }
            );
        }

        my $patron = Koha::Patrons->find($patron_id);
        unless ($patron) {
            return $c->render(
                status  => 409,
                openapi => {
                    error      => 'Patron not found',
                    error_code => 'PATRON_NOT_FOUND',
                }
            );
        }

        my ( $impossible, $confirmation, $warnings ) = $c->_check_availability( $patron, $item );

        # * Fail for blockers - render 403
        if ( keys %{$impossible} ) {
            my @errors = keys %{$impossible};
            return $c->render(
                status  => 403,
                openapi => { error => "Checkout not authorized (@errors)" }
            );
        }

        # * If confirmation required, check variable set above
        #   and render 412 if variable is false
        if ( keys %{$confirmation} ) {
            my $confirmed = 0;

            # Check for existence of confirmation token
            # and if exists check validity
            if ( my $token = $c->param('confirmation') ) {
                my $confirm_keys = join( ":", sort keys %{$confirmation} );
                $confirm_keys = $user->id . ":" . $item->id . ":" . $confirm_keys;
                $confirmed    = Koha::Token->new->check_jwt( { id => $confirm_keys, token => $token } );
            }

            unless ($confirmed) {
                return $c->render(
                    status  => 412,
                    openapi => { error => "Confirmation error" }
                );
            }
        }

        # Call 'AddIssue'
        my $checkout = AddIssue(
            $patron,
            $item->barcode,
            undef, undef, undef, undef,
            {
                confirmations => [ grep { /^[A-Z_]+$/ } keys %{$confirmation} ],
                forced        => [ keys %{$impossible} ]
            }
        );
        if ($checkout) {
            $c->res->headers->location( $c->req->url->to_string . '/' . $checkout->id );
            return $c->render(
                status  => 201,
                openapi => $c->objects->to_api($checkout),
            );
        } else {
            return $c->render(
                status  => 500,
                openapi => { error => 'Unknown error during checkout' }
            );
        }
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 get_renewals

List Koha::Checkout::Renewals

=cut

sub get_renewals {
    my $c = shift->openapi->valid_input or return;

    try {
        my $checkout_id = $c->param('checkout_id');

        my $checkout = Koha::Checkouts->find($checkout_id);
        $checkout = Koha::Old::Checkouts->find($checkout_id)
            unless $checkout;

        return $c->render_resource_not_found("Checkout")
            unless $checkout;

        my $renewals_rs = $checkout->renewals;
        my $renewals    = $c->objects->search($renewals_rs);

        return $c->render(
            status  => 200,
            openapi => $renewals
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 renew

Renew a checkout

=cut

sub renew {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->param('checkout_id');
    my $seen        = $c->param('seen') || 1;
    my $checkout    = Koha::Checkouts->find($checkout_id);

    return $c->render_resource_not_found("Checkout")
        unless $checkout;

    return try {
        my $body = $c->req->json;
        my $due_date;
        if ( $body && $body->{due_date} ) {
            $due_date = eval { dt_from_string( $body->{due_date}, 'rfc3339' ) };
            return $c->render_invalid_parameter_value( { path => '/body/due_date' } )
                unless $due_date;
        }

        my $overrides = $c->stash('koha.overrides');
        my $override_limit =
            ( $overrides->{renewal_limit} && C4::Context->preference("AllowRenewalLimitOverride") )
            ? 1
            : 0;

        my ( $can_renew, $error ) = CanBookBeRenewed( $checkout->patron, $checkout, $override_limit, undef, $due_date );

        my $confirmations = [];
        push @{$confirmations}, 'RENEWAL_LIMIT' if $override_limit;

        # Check if error is due to excessive fines and override is requested
        if ( !$can_renew && ( $error eq 'too_much_owing' or $error eq 'auto_too_much_owing' ) ) {
            if ( $overrides->{debt_limit} && C4::Context->preference("AllowFineOverrideRenewing") ) {

                # Override is allowed, proceed with renewal
                $can_renew = 1;
                $error     = undef;
            }
        }

        if ( !$can_renew ) {
            return $c->render(
                status  => 403,
                openapi => {
                    error      => "Renewal not authorized ($error)",
                    error_code => $error,
                }
            );
        }

        AddRenewal(
            {
                borrowernumber => $checkout->borrowernumber,
                itemnumber     => $checkout->itemnumber,
                branch         => $checkout->branchcode,
                seen           => $seen,
                datedue        => $due_date,
                confirmations  => $confirmations,
            }
        );
        $checkout = Koha::Checkouts->find($checkout_id);

        $c->res->headers->location( $c->req->url->to_string );
        return $c->render(
            status  => 201,
            openapi => $c->objects->to_api($checkout),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 allows_renewal

Checks if the checkout could be renewed and return the related information.

=cut

sub allows_renewal {
    my $c = shift->openapi->valid_input or return;

    my $checkout_id = $c->param('checkout_id');
    my $checkout    = Koha::Checkouts->find($checkout_id);

    return $c->render_resource_not_found("Checkout")
        unless $checkout;

    return try {
        my ( $can_renew, $error ) = CanBookBeRenewed( $checkout->patron, $checkout );

        my $renewable = Mojo::JSON->false;
        $renewable = Mojo::JSON->true if $can_renew;

        my $rule = Koha::CirculationRules->get_effective_rule(
            {
                categorycode => $checkout->patron->categorycode,
                itemtype     => $checkout->item->effective_itemtype,
                branchcode   => $checkout->branchcode,
                rule_name    => 'renewalsallowed',
            }
        );
        return $c->render(
            status  => 200,
            openapi => {
                allows_renewal   => $renewable,
                max_renewals     => $rule->rule_value,
                current_renewals => $checkout->renewals_count,
                unseen_renewals  => $checkout->unseen_renewals,
                error            => $error
            }
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head2 Internal methods

=head3 _checkout_library_id

    my $library_id = $c->_checkout_library_id( $library_id, $path ) or return;

Returns the library the checkout takes place at: I<$library_id> if passed,
the logged in user's library otherwise. Renders the error response and
returns undef when I<$library_id> is not a valid library (400), or when the
user cannot act at that library (403, I<library_not_allowed>), as decided by
L<Koha::Patron/can_log_into> (the same check the I<x-koha-library> header
goes through). I<$path> is the parameter path reported in the 400 response.

=cut

sub _checkout_library_id {
    my ( $c, $library_id, $path ) = @_;

    my $user_library_id = C4::Context->userenv->{branch};

    return $user_library_id
        unless defined $library_id;

    my $library = Koha::Libraries->find($library_id);
    unless ($library) {
        $c->render_invalid_parameter_value( { path => $path } );
        return;
    }

    # FIXME: Koha::Libraries has no search_limited yet. Adding one would also
    # limit GET /libraries, as the objects helpers use it when available.
    unless ( $c->stash('koha.user')->can_log_into($library) ) {
        $c->render(
            status  => 403,
            openapi => {
                error      => 'Checkouts are restricted to the logged in library',
                error_code => 'library_not_allowed',
            }
        );
        return;
    }

    return $library_id;
}

=head3 _checkout_availability

    my $availability = $c->_checkout_availability(
        { item => $item, patron => $patron, library => $library_id } );

Returns the L<Koha::Item::Availability::Checkout::Result> for the request,
with the overrides passed in the I<x-koha-override> header.

=cut

sub _checkout_availability {
    my ( $c, $params ) = @_;

    return $params->{item}->checkout_availability(
        {
            patron    => $params->{patron},
            user      => $c->stash('koha.user'),
            library   => $params->{library},
            interface => 'intranet',
            overrides => $c->stash('koha.overrides') // {},
        }
    );
}

1;
