package Koha::REST::V1::DeletedItems;

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

use Koha::Exceptions;
use Koha::Exceptions::Object;
use Koha::Old::Items;

use Scalar::Util qw( blessed );
use Try::Tiny    qw( catch try );

=head1 API

=head2 Methods

=head3 get

Controller function that handles retrieving a single deleted item object

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $item = Koha::Old::Items->find( $c->param('item_id') );

    return $c->render_resource_not_found("Item")
        unless $item;

    return try {
        return $c->render(
            status  => 200,
            openapi => $c->objects->to_api($item),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 list

Controller function that handles listing deleted item objects

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $items = $c->objects->search( Koha::Old::Items->new );
        return $c->render( status => 200, openapi => $items );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 restore

Controller function that handles restoring a single deleted item object

=cut

sub restore {
    my $c = shift->openapi->valid_input or return;

    my $deleted_item = Koha::Old::Items->find( $c->param('item_id') );

    return $c->render_resource_not_found("Item")
        unless $deleted_item;

    return try {
        my $patron = $c->stash('koha.user');

        unless ( $patron->can_edit_items_from( $deleted_item->homebranch ) ) {
            return $c->render(
                status  => 403,
                openapi => { error => "You do not have permission to restore items from this library." }
            );
        }

        my $item = $deleted_item->restore;

        return $c->render(
            status  => 200,
            openapi => $c->objects->to_api($item),
        );
    } catch {
        if ( blessed $_ && $_->isa('Koha::Exceptions::ObjectNotFound') ) {
            return $c->render(
                status  => 409,
                openapi => {
                    error =>
                        "Bibliographic record not found for this item. Cannot restore item without its bibliographic record."
                }
            );
        }
        if ( blessed $_ && $_->isa('Koha::Exceptions::Object::DuplicateID') ) {
            return $c->render(
                status  => 409,
                openapi => { error => "Cannot restore item: another item with the same barcode already exists." }
            );
        }
        $c->unhandled_exception($_);
    };
}

1;
