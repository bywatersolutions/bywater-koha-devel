package Koha::Z3950Server;

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

use Koha::Database;

use base qw(Koha::Object Koha::Object::Limit::Library);

=head1 NAME

Koha::Z3950Server - Koha Z3950Server Object class

=head1 API

=head2 Internal methods

=head3 _library_limits

Configure library limits for Z39.50 servers

=cut

sub _library_limits {
    return {
        class   => "Z3950serversBranch",
        id      => "server_id",
        library => "branchcode",
    };
}

=head3 _type

Return type of Object relating to Schema ResultSet

=cut

sub _type {
    return 'Z3950server';
}

1;
