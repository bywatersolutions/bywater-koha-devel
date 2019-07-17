package Koha::REST::V1::ReturnClaims;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Checkouts::ReturnClaims;
use Koha::Checkouts;
use Koha::DateUtils qw( dt_from_string output_pref );

=head1 NAME

Koha::REST::V1::ReturnClaims

=head2 Operations

=head3 claim_returned

Claim that a checked out item was returned.

=cut

sub claim_returned {
    my $c     = shift->openapi->valid_input or return;
    my $input = $c->validation->output;
    my $body  = $c->validation->param('body');

    my $itemnumber      = $input->{item_id};
    my $charge_lost_fee = $body->{charge_lost_fee} ? 1 : 0;
    my $created_by      = $body->{created_by};
    my $notes           = $body->{notes};

    my $checkout = Koha::Checkouts->find( { itemnumber => $itemnumber } );

    return $c->render(
        openapi => { error => "Not found - Checkout not found" },
        status  => 404
    ) unless $checkout;

    my $claim = Koha::Checkouts::ReturnClaims->find(
        {
            issue_id => $checkout->id
        }
    );
    return $c->render(
        openapi => { error => "Bad request - claim exists" },
        status  => 400
    ) if $claim;

    $claim = $checkout->claim_returned(
        {
            charge_lost_fee => $charge_lost_fee,
            created_by      => $created_by,
            notes           => $notes,
        }
    );

    my $data = $claim->unblessed;

    my $c_dt = dt_from_string( $data->{created_on} );
    my $u_dt = dt_from_string( $data->{updated_on} );

    $data->{created_on_formatted} = output_pref( { dt => $c_dt } );
    $data->{updated_on_formatted} = output_pref( { dt => $u_dt } );

    $data->{created_on} = $c_dt->iso8601;
    $data->{updated_on} = $u_dt->iso8601;

    return $c->render( openapi => $data, status => 200 );
}

sub update_notes {
    my $c     = shift->openapi->valid_input or return;
    my $input = $c->validation->output;
    my $body  = $c->validation->param('body');

    my $id         = $input->{claim_id};
    my $updated_by = $body->{updated_by};
    my $notes      = $body->{notes};

    $updated_by ||=
      C4::Context->userenv ? C4::Context->userenv->{number} : undef;

    my $claim = Koha::Checkouts::ReturnClaims->find($id);

    return $c->render(
        openapi => { error => "Not found - Claim not found" },
        status  => 404
    ) unless $claim;

    $claim->set(
        {
            notes      => $notes,
            updated_by => $updated_by,
            updated_on => dt_from_string(),
        }
    );
    $claim->store();

    my $data = $claim->unblessed;

    my $c_dt = dt_from_string( $data->{created_on} );
    my $u_dt = dt_from_string( $data->{updated_on} );

    $data->{created_on_formatted} = output_pref( { dt => $c_dt } );
    $data->{updated_on_formatted} = output_pref( { dt => $u_dt } );

    $data->{created_on} = $c_dt->iso8601;
    $data->{updated_on} = $u_dt->iso8601;

    return $c->render( openapi => $data, status => 200 );
}

sub resolve_claim {
    my $c     = shift->openapi->valid_input or return;
    my $input = $c->validation->output;
    my $body  = $c->validation->param('body');

    my $id          = $input->{claim_id};
    my $resolved_by = $body->{updated_by};
    my $resolution  = $body->{resolution};

    $resolved_by ||=
      C4::Context->userenv ? C4::Context->userenv->{number} : undef;

    my $claim = Koha::Checkouts::ReturnClaims->find($id);

    return $c->render(
        openapi => { error => "Not found - Claim not found" },
        status  => 404
    ) unless $claim;

    $claim->set(
        {
            resolution  => $resolution,
            resolved_by => $resolved_by,
            resolved_on => dt_from_string(),
        }
    );
    $claim->store();

    my $data = $claim->unblessed;

    my $c_dt = dt_from_string( $data->{created_on} );
    my $u_dt = dt_from_string( $data->{updated_on} );
    my $r_dt = dt_from_string( $data->{resolved_on} );

    $data->{created_on_formatted}  = output_pref( { dt => $c_dt } );
    $data->{updated_on_formatted}  = output_pref( { dt => $u_dt } );
    $data->{resolved_on_formatted} = output_pref( { dt => $r_dt } );

    $data->{created_on}  = $c_dt->iso8601;
    $data->{updated_on}  = $u_dt->iso8601;
    $data->{resolved_on} = $r_dt->iso8601;

    return $c->render( openapi => $data, status => 200 );
}

sub delete_claim {
    my $c     = shift->openapi->valid_input or return;
    my $input = $c->validation->output;

    my $id         = $input->{claim_id};

    my $claim = Koha::Checkouts::ReturnClaims->find($id);

    return $c->render(
        openapi => { error => "Not found - Claim not found" },
        status  => 404
    ) unless $claim;

    $claim->delete();

    my $data = $claim->unblessed;

    return $c->render( openapi => $data, status => 200 );
}

1;
