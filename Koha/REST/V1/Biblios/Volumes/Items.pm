package Koha::REST::V1::Biblios::Volumes::Items;

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

use Koha::Biblio::Volume::Items;

use Scalar::Util qw(blessed);
use Try::Tiny;

=head1 NAME

Koha::REST::V1::Biblios::Volumes::Items - Koha REST API for handling volume items (V1)

=head1 API

=head2 Methods

=head3 add

Controller function to handle adding a Koha::Biblio::Volume object

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    return try {

        my $volume = Koha::Biblio::Volumes->find(
            $c->validation->param('volume_id')
        );

        unless ( $volume ) {
            return $c->render(
                status  => 404,
                openapi => {
                    error => 'Volume not found'
                }
            );
        }

        unless ( $volume->biblionumber eq $c->validation->param('biblio_id') ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error => 'Volume does not belong to passed biblio_id'
                }
            );
        }

        # All good, add the item
        my $body    = $c->validation->param('body');
        my $item_id = $body->{item_id};

        $volume->add_item({ item_id => $item_id });

        $c->res->headers->location( $c->req->url->to_string . '/' . $item_id );

        my $embed = $c->stash('koha.embed');

        return $c->render(
            status  => 201,
            openapi => $volume->to_api({ embed => $embed })
        );
    }
    catch {
        if ( blessed($_) ) {

            if ( $_->isa('Koha::Exceptions::Object::FKConstraint') ) {
                if ( $_->broken_fk eq 'itemnumber' ) {
                    return $c->render(
                        status  => 409,
                        openapi => {
                            error => "Given item_id does not exist"
                        }
                    );
                }
                elsif ( $_->broken_fk eq 'biblionumber' ) {
                    return $c->render(
                        status  => 409,
                        openapi => {
                            error => "Given item_id does not belong to the volume's biblio"
                        }
                    );
                }
            }
            elsif ( $_->isa('Koha::Exceptions::Object::DuplicateID') ) {

                return $c->render(
                    status  => 409,
                    openapi => {
                        error => "The given item_id is already linked to the volume"
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

    my $volume_id = $c->validation->param('volume_id');
    my $item_id   = $c->validation->param('item_id');

    my $item_link = Koha::Biblio::Volume::Items->find(
        {
            itemnumber => $item_id,
            volume_id  => $volume_id
        }
    );

    unless ( $item_link ) {
        return $c->render(
            status  => 404,
            openapi => {
                error => 'No such volume <-> item relationship'
            }
        );
    }

    return try {
        $item_link->delete;
        return $c->render(
            status  => 204,
            openapi => q{}
        );
    }
    catch {
        $c->unhandled_exception($_);
    };
}

1;
