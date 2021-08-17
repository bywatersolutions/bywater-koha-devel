package Koha::REST::V1::Biblios::Volumes;

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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Biblio::Volumes;

use Scalar::Util qw(blessed);
use Try::Tiny;

=head1 NAME

Koha::REST::V1::Biblios::Volumes - Koha REST API for handling volumes (V1)

=head1 API

=head2 Methods

=cut

=head3 list

Controller function that handles listing Koha::Biblio::Volume objects

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $volumes_set = Koha::Biblio::Volumes->new;
        my $volumes     = $c->objects->search( $volumes_set );
        return $c->render(
            status  => 200,
            openapi => $volumes
        );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

=head3 get

Controller function that handles retrieving a single Koha::Biblio::Volume

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    try {
        my $volume_id = $c->validation->param('volume_id');
        my $biblio_id = $c->validation->param('biblio_id');

        my $volume = Koha::Biblio::Volumes->find( $volume_id );
        my $embed = $c->stash('koha.embed');

        if ( $volume && $volume->biblionumber eq $biblio_id ) {
            return $c->render(
                status  => 200,
                openapi => $volume->to_api({ embed => $embed })
            );
        }
        else {
            return $c->render(
                status  => 404,
                openapi => {
                    error => 'Volume not found'
                }
            );
        }
    }
    catch {
        $c->unhandled_exception($_);
    };
}

=head3 add

Controller function to handle adding a Koha::Biblio::Volume object

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $volume_data = $c->validation->param('body');
        # biblio_id comes from the path
        $volume_data->{biblio_id} = $c->validation->param('biblio_id');

        my $volume = Koha::Biblio::Volume->new_from_api($volume_data);
        $volume->store->discard_changes();

        $c->res->headers->location( $c->req->url->to_string . '/' . $volume->id );

        return $c->render(
            status  => 201,
            openapi => $volume->to_api
        );
    }
    catch {
        if ( blessed($_) ) {
            my $to_api_mapping = Koha::Biblio::Volume->new->to_api_mapping;

            if ( $_->isa('Koha::Exceptions::Object::FKConstraint') and
                 $to_api_mapping->{ $_->broken_fk } eq 'biblio_id') {
                return $c->render(
                    status  => 404,
                    openapi => { error => "Biblio not found" }
                );
            }
        }

        $c->unhandled_exception($_);
    };
}

=head3 update

Controller function to handle updating a Koha::Biblio::Volume object

=cut

sub update {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $volume_id = $c->validation->param('volume_id');
        my $biblio_id = $c->validation->param('biblio_id');

        my $volume = Koha::Biblio::Volumes->find( $volume_id );

        unless ( $volume && $volume->biblionumber eq $biblio_id ) {
            return $c->render(
                status  => 404,
                openapi => {
                    error => 'Volume not found'
                }
            );
        }

        my $volume_data = $c->validation->param('body');
        $volume->set_from_api( $volume_data )->store->discard_changes();

        return $c->render(
            status  => 200,
            openapi => $volume->to_api
        );
    }
    catch {
        if ( blessed($_) ) {
            my $to_api_mapping = Koha::Biblio::Volume->new->to_api_mapping;

            if ( $_->isa('Koha::Exceptions::Object::FKConstraint') ) {
                return $c->render(
                    status  => 409,
                    openapi => {
                        error => "Given " . $to_api_mapping->{ $_->broken_fk } . " does not exist"
                    }
                );
            }
        }

        $c->unhandled_exception($_);
    };
}

=head3 delete

Controller function that handles deleting a Koha::Biblio::Volume object

=cut

sub delete {

    my $c = shift->openapi->valid_input or return;

    my $volume_id = $c->validation->param( 'volume_id' );
    my $biblio_id = $c->validation->param( 'biblio_id' );

    my $volume = Koha::Biblio::Volumes->find({ id => $volume_id, biblionumber => $biblio_id });

    if ( not defined $volume ) {
        return $c->render( status => 404, openapi => { error => "Volume not found" } );
    }

    return try {
        $volume->delete;
        return $c->render( status => 204, openapi => '');
    }
    catch {
        $c->unhandled_exception($_);
    };
}

1;
