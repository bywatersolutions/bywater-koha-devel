package Koha::REST::V1::Checkins;

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

use Mojo::Base 'Mojolicious::Controller';

use C4::Circulation qw( AddReturn );
use C4::Context;
use Koha::Checkouts;
use Koha::DateUtils qw( dt_from_string );
use Koha::Items;
use Koha::Libraries;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

=head1 NAME

Koha::REST::V1::Checkins

=head1 API

=head2 Methods

=head3 get_availability

=cut

sub get_availability {
    my $c    = shift->openapi->valid_input or return;
    my $user = $c->stash('koha.user');

    my $item_id = $c->param('item_id');

    # Default to the logged in user's library, same fallback AddReturn
    # itself applies, so the dry-run answers the same question the real
    # checkin will.
    my $library_id = $c->param('library_id') // C4::Context->userenv->{branch};

    my $item = Koha::Items->find($item_id);

    return $c->render_resource_not_found("Item")
        unless $item;

    return try {
        my $availability = $item->checkin_availability(
            {
                library          => $library_id,
                no_short_circuit => 1,
            }
        );

        $availability->set_context( item => $item );
        $availability->set_context( user => $user );

        return $c->render(
            status  => 200,
            openapi => $availability->to_api,
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

=cut

sub add {
    my $c    = shift->openapi->valid_input or return;
    my $user = $c->stash('koha.user');

    my $body        = $c->req->json;
    my $item_id     = $body->{item_id};
    my $barcode     = $body->{external_id};
    my $library_id  = $body->{library_id} // $user->branchcode;
    my $exemptfine  = $body->{exempt_fine};
    my $return_date = $body->{return_date};
    my $dropboxmode = $body->{dropbox_mode};

    return try {

        # Enforce writeoff permission for exempt_fine
        if ($exemptfine) {
            unless ( $user->has_permission( { updatecharges => 'writeoff' } ) ) {
                return $c->render(
                    status  => 403,
                    openapi => {
                        error      => 'Fine exemption requires updatecharges.writeoff permission',
                        error_code => 'no_permission_for_exempt_fine',
                        policy     => $c->module_policy( 'Checkin', { library => $library_id } ),
                    }
                );
            }
        }

        # Enforce SpecifyReturnDate preference for return_date
        if ($return_date) {
            unless ( C4::Context->preference('SpecifyReturnDate') ) {
                return $c->render(
                    status  => 403,
                    openapi => {
                        error      => 'Return date override is not enabled',
                        error_code => 'return_date_not_allowed',
                        policy     => $c->module_policy( 'Checkin', { library => $library_id } ),
                    }
                );
            }
        }

        unless ( $item_id or $barcode ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => 'Missing item_id or external_id',
                    error_code => 'missing_item_identifier',
                }
            );
        }

        if ( $item_id and $barcode ) {
            return $c->render(
                status  => 400,
                openapi => {
                    error      => 'item_id and external_id are mutually exclusive',
                    error_code => 'mutually_exclusive_parameters',
                }
            );
        }

        my $item;
        if ($item_id) {
            $item = Koha::Items->find($item_id);
        } else {
            $item = Koha::Items->find( { barcode => $barcode } );
        }

        return $c->render_resource_not_found("Item")
            unless $item;

        my $availability = $item->checkin_availability(
            {
                library          => $library_id,
                no_short_circuit => 1,
            }
        );

        if ( !$availability->available ) {
            return $c->render(
                status  => 403,
                openapi => {
                    error      => 'Checkin blocked',
                    error_code => 'checkin_blocked',
                    blockers   => $availability->blockers,
                    item       => $item->to_api( { embed => { biblio => {} } } ),
                }
            );
        }

        if ( $availability->needs_confirmation ) {

            $availability->set_context( item => $item );
            $availability->set_context( user => $user );

            my $confirmed = 0;

            if ( my $token = $c->param('confirmation') ) {
                $confirmed = $availability->check_token($token);
            }

            # A caller may opt out of specific confirmations via x-koha-override.
            # The 'not_issued' confirmation (item was not checked out) can be
            # overridden so the check-in is recorded directly - matching the
            # legacy returns page, which never prompts for a not-issued item.
            #
            # NOTE: overrides are handled here in the controller, consistent
            # with the other REST endpoints (checkouts, holds, ...). Once a
            # Koha::Circulation->checkin business-logic method exists, the
            # overrides should be passed down to it so the domain layer owns
            # this decision instead of the controller.
            unless ($confirmed) {
                my $overrides     = $c->stash('koha.overrides') // {};
                my @confirmations = keys %{ $availability->confirmations };
                if (   $overrides->{not_issued}
                    && scalar(@confirmations) == 1
                    && $confirmations[0] eq 'not_issued' )
                {
                    $confirmed = 1;
                }
            }

            unless ($confirmed) {
                return $c->render(
                    status  => 412,
                    openapi => {
                        error      => 'Confirmation required',
                        error_code => 'confirmation_required',
                        item       => $item->to_api( { embed => { biblio => {} } } ),
                        %{ $availability->to_api },
                    }
                );
            }
        }

        # TODO: Move date calculation into Koha::Circulation->checkin when it exists.
        # The controller should pass intent (dropbox => 1, return_date => $string)
        # and the domain layer should handle the calculation internally.
        my $effective_return_date;
        if ($dropboxmode) {
            $effective_return_date = Koha::Checkouts->calculate_dropbox_date();
        } elsif ($return_date) {
            $effective_return_date = dt_from_string($return_date);
        }

        my ( $doreturn, $messages, $issue, $borrower, $checkin ) = AddReturn(
            $item->barcode,
            $library_id,
            $exemptfine,
            $effective_return_date,
        );

        # TODO: Move the post-return processing below into Koha::Circulation->checkin
        # when it exists, as with the date calculation above.

        # Wrong transfer: replace the transfer so it starts from where the item really is
        if ( $messages->{WrongTransfer} && !$messages->{WasTransfered} ) {
            $checkin->replace_wrong_transfer;
        }

        # HoldsAutoFill: fill the hold that was found instead of asking for confirmation
        my $hold_found = $messages->{ResFound};
        if (   $hold_found
            && $hold_found->{ResFound} ne 'Waiting'
            && C4::Context->preference('HoldsAutoFill') )
        {
            $checkin->confirm_hold;
            $checkin->add_message(
                {
                    message => 'hold_auto_filled',
                    type    => 'info',
                    payload => {
                        reserve_id => $hold_found->{reserve_id},
                        library_id => $hold_found->{branchcode},
                    },
                }
            );
        }

        # Bundle verification: mark missing items as lost, remove unexpected ones
        if ( $item->is_bundle && defined $body->{verified_bundle_barcodes} ) {
            my $result = $checkin->verify_bundle(
                {
                    verified_barcodes => $body->{verified_bundle_barcodes},
                    patron_id         => $borrower ? $borrower->{borrowernumber} : undef,
                }
            );
            my %bundle_messages = (
                bundle_missing_items    => $result->{missing},
                bundle_unexpected_items => $result->{unexpected},
            );
            for my $message ( sort keys %bundle_messages ) {
                my @items = @{ $bundle_messages{$message} };
                next unless @items;
                $checkin->add_message(
                    {
                        message => $message,
                        type    => 'warning',
                        payload => {
                            items => [
                                map {
                                    {
                                        item_id     => $_->itemnumber,
                                        external_id => $_->barcode,
                                        title       => $_->biblio->title,
                                    }
                                } @items
                            ],
                        },
                    }
                );
            }
        }

        # Serialize outcome messages from the checkin object so API consumers
        # see the full result, not just the subset with a dedicated FK column
        my @messages = map {
            my $msg = { message => $_->message, type => $_->type };
            $msg->{payload} = $_->payload if defined $_->payload;
            $msg;
        } @{ $checkin->object_messages };

        my $response = $c->objects->find( Koha::Checkins->new, $checkin->id );
        $response->{messages} = \@messages if @messages;

        return $c->render(
            status  => 200,
            openapi => $response,
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 hold_confirmation

POST /checkins/{checkin_id}/hold_confirmation

=cut

sub hold_confirmation {
    my $c = shift->openapi->valid_input or return;

    my $checkin = Koha::Checkins->find( $c->param('checkin_id') );
    return $c->render_resource_not_found("Checkin") unless $checkin;

    return $c->render( status => 400, openapi => { error => "No hold associated with this checkin" } )
        unless $checkin->hold_id;

    return try {
        $checkin->confirm_hold;
        return $c->_render_checkin_response($checkin);
    } catch {
        if ( blessed $_ && $_->isa('Koha::Exceptions::Checkin::ItemCheckedOut') ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error =>
                        'The item has been checked out in the meantime: the hold has not been set aside and remains pending',
                    error_code => 'item_checked_out',
                }
            );
        }
        $c->unhandled_exception($_);
    };
}

=head3 hold_cancellation

POST /checkins/{checkin_id}/hold_cancellation

=cut

sub hold_cancellation {
    my $c = shift->openapi->valid_input or return;

    my $checkin = Koha::Checkins->find( $c->param('checkin_id') );
    return $c->render_resource_not_found("Checkin") unless $checkin;

    return $c->render( status => 400, openapi => { error => "No hold associated with this checkin" } )
        unless $checkin->hold_id;

    my $body = $c->req->json // {};
    my $user = $c->stash('koha.user');

    # Enforce writeoff permission for forgive_hold_fees
    if ( $body->{forgive_hold_fees} ) {
        unless ( $user->has_permission( { updatecharges => 'writeoff' } ) ) {
            return $c->render(
                status  => 403,
                openapi => {
                    error      => 'Forgiving hold fees requires updatecharges.writeoff permission',
                    error_code => 'no_permission_for_forgive_hold_fees',
                    policy     => $c->module_policy( 'Checkin', { library => $checkin->library_id } ),
                }
            );
        }
    }

    return try {
        $checkin->cancel_hold(
            {
                reason            => $body->{reason},
                forgive_hold_fees => $body->{forgive_hold_fees} ? 1 : 0,
            }
        );
        return $c->_render_checkin_response($checkin);
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 transfer_confirmation

POST /checkins/{checkin_id}/transfer_confirmation

=cut

sub transfer_confirmation {
    my $c = shift->openapi->valid_input or return;

    my $checkin = Koha::Checkins->find( $c->param('checkin_id') );
    return $c->render_resource_not_found("Checkin") unless $checkin;

    my $body = $c->req->json // {};

    # No transfer yet (AutomaticItemReturn disabled): the destination is required
    unless ( $checkin->transfer_id ) {
        return $c->render( status => 400, openapi => { error => "No transfer associated with this checkin" } )
            unless $body->{to_library_id};

        return $c->render( status => 400, openapi => { error => "Library not found" } )
            unless Koha::Libraries->find( $body->{to_library_id} );
    }

    return try {
        $checkin->confirm_transfer(
            {
                to_library_id => $body->{to_library_id},
                reason        => $body->{reason},
            }
        );
        return $c->_render_checkin_response($checkin);
    } catch {
        if ( blessed $_ ) {
            if ( $_->isa('Koha::Exceptions::Item::Transfer::Limit') ) {
                return $c->render(
                    status  => 409,
                    openapi => {
                        error      => 'Transfer not allowed by the branch transfer limits',
                        error_code => 'transfer_limit',
                    }
                );
            }
            if ( $_->isa('Koha::Exceptions::Item::Transfer::InQueue') ) {
                return $c->render(
                    status  => 409,
                    openapi => {
                        error      => 'The item already has a pending transfer',
                        error_code => 'transfer_in_queue',
                    }
                );
            }
        }
        $c->unhandled_exception($_);
    };
}

=head3 transfer_cancellation

POST /checkins/{checkin_id}/transfer_cancellation

=cut

sub transfer_cancellation {
    my $c = shift->openapi->valid_input or return;

    my $checkin = Koha::Checkins->find( $c->param('checkin_id') );
    return $c->render_resource_not_found("Checkin") unless $checkin;

    return $c->render( status => 400, openapi => { error => "No transfer associated with this checkin" } )
        unless $checkin->transfer_id;

    return try {
        $checkin->cancel_transfer;
        return $c->_render_checkin_response($checkin);
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 recall_confirmation

POST /checkins/{checkin_id}/recall_confirmation

=cut

sub recall_confirmation {
    my $c = shift->openapi->valid_input or return;

    my $checkin = Koha::Checkins->find( $c->param('checkin_id') );
    return $c->render_resource_not_found("Checkin") unless $checkin;

    return $c->render( status => 400, openapi => { error => "No recall associated with this checkin" } )
        unless $checkin->recall_id;

    return try {
        $checkin->confirm_recall;
        return $c->_render_checkin_response($checkin);
    } catch {
        $c->unhandled_exception($_);
    };
}

=head2 Internal methods

=head3 _render_checkin_response

Renders the standard checkin response with Location header.

=cut

sub _render_checkin_response {
    my ( $c, $checkin ) = @_;

    $checkin->discard_changes;

    my $response = $c->objects->find( Koha::Checkins->new, $checkin->id );

    $c->res->headers->location( $c->req->url->to_string . '/' . $checkin->id );

    return $c->render(
        status  => 201,
        openapi => $response,
    );
}

1;
