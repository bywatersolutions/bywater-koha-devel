package Koha::Permission;

# Copyright ByWater Solutions 2017
#
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

use Carp;

use Koha::Patron::Permissions;

use base qw(Koha::Object);

=head1 NAME

Koha::Permission - Koha Permission Object class

=head1 API

=head2 Class Methods

=cut

=head3  patron_has

    Accepts a patron id, returns true if patron has this permission, false otherwise
=cut

sub patron_has {
    my ( $self, $patron ) = @_;

    return Koha::Patron::Permissions->find( { borrowernumber => $patron, code => $self->code } ) ? 1 : 0;
}

=head3 subpermissions

=cut

sub subpermissions {
    my ( $self ) = @_;

    return Koha::Permissions->search( { parent => $self->code } );
}

=head3 type

=cut

sub _type {
    return 'Permission';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
