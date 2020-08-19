package Koha::Biblio::Volume;

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

use base qw(Koha::Object);

use Koha::Biblio::Volume::Items;
use Koha::Exceptions::Object;
use Koha::Items;

=head1 NAME

Koha::Volume - Koha Volume Object class

=head1 API

=head2 Class methods

=head3 store

    $volume->store;

Overloaded I<store> method that takes care of creation date handling.

=cut

sub store {
    my ($self) = @_;

    unless ( $self->in_storage ) {
        # new entry
        $self->set(
            {
                created_on => \'NOW()'
            }
        );
    }

    return $self->SUPER::store();
}

=head3 items

    my $items = $volume->items;

Returns all the items linked to the volume.

=cut

sub items {
    my ($self) = @_;

    my $items_rs = $self->_result->volume_items;
    my @item_numbers = $items_rs->get_column('itemnumber')->all;

    return unless @item_numbers;

    return Koha::Items->search(
        {
            itemnumber => {
                -in => \@item_numbers
            }
        }
    );
}

=head3 add_item

    $volume->add_item({ item_id => $item_id });

=cut

sub add_item {
    my ($self, $params) = @_;

    my $item_id = $params->{item_id};

    my $item = Koha::Items->find( $item_id );
    unless ( $item->biblionumber == $self->biblionumber ) {
        Koha::Exceptions::Object::FKConstraint->throw(
            broken_fk => 'biblionumber'
        );
    }

    Koha::Biblio::Volume::Item->new(
        {
            itemnumber => $item_id,
            volume_id  => $self->id
        }
    )->store;

    return $self;
}

=head3 to_api_mapping

This method returns the mapping for representing a Koha::Biblio::Volume object
on the API.

=cut

sub to_api_mapping {
    return {
        id           => 'volume_id',
        biblionumber => 'biblio_id',
        created_on   => 'creation_date',
        updated_on   => 'modification_date'
    };
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'Volume';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::Biblio::Volume';
}

1;
