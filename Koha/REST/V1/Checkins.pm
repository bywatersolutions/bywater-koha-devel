package Koha::REST::V1::Checkins;

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
use Koha::Checkins;
use Koha::Checkouts;
use Koha::DateUtils qw(dt_from_string);
use Koha::Items;

use Try::Tiny qw( catch try );

=head1 NAME

Koha::REST::V1::Checkins

=head1 API

=head2 Methods

=head3 get_availability

=cut

sub get_availability {
    my $c    = shift->openapi->valid_input or return;
    my $user = $c->stash('koha.user');

    my $item_id    = $c->param('item_id');
    my $library_id = $c->param('library_id');

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

        $c->attach_module_policy( 'Checkin', { library => $library_id } );

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
    my $library_id  = $body->{library_id};
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

            unless ($confirmed) {
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

        # Serialize messages from the checkin object
        my @messages = map {
            my $msg = { message => $_->message, type => $_->type };
            $msg->{payload} = $_->payload if defined $_->payload;
            $msg;
        } @{ $checkin->object_messages };

        my $response = $c->objects->to_api($checkin);
        $response->{messages} = \@messages if @messages;

        $c->attach_module_policy( 'Checkin', { library => $library_id } );

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

    return try {
        $checkin->cancel_hold( { reason => $body->{reason} } );
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

    return $c->render( status => 400, openapi => { error => "No transfer associated with this checkin" } )
        unless $checkin->transfer_id;

    return try {
        $checkin->confirm_transfer;
        return $c->_render_checkin_response($checkin);
    } catch {
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

Renders the standard checkin response with Location header and policy.

=cut

sub _render_checkin_response {
    my ( $c, $checkin ) = @_;

    $checkin->discard_changes;

    my $response = $c->objects->to_api($checkin);

    $c->attach_module_policy( 'Checkin', { library => $checkin->library_id } );
    $c->res->headers->location( "/api/v1/checkins/" . $checkin->id );

    return $c->render(
        status  => 201,
        openapi => $response,
    );
}

1;
