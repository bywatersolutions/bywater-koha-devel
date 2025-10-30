package Koha::Old::Item;

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

use base qw(Koha::Object);

use Koha::Item;

=head1 NAME

Koha::Old::Item - Koha Old::Item Object class

=head1 API

=head2 Class methods

=cut

=head3 restore

    my $item = $deleted_item->restore;

Restores the deleted item record back to the items table. This removes
the record from the deleteditems table and re-inserts it into the items table.

Returns the newly restored Koha::Item object.

=cut

sub restore {
    my ($self) = @_;

    my $item_data = $self->unblessed;
    delete $item_data->{deleted_on};

    my $new_item = Koha::Item->new($item_data)->store;

    $self->delete;

    return $new_item;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'Deleteditem';
}

1;
