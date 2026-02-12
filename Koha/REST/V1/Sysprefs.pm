package Koha::REST::V1::Sysprefs;

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

use Koha::Config::SysPrefs;

use Try::Tiny;

=head1 API

=head2 Methods

=head3 list_sysprefs

This routine returns the system preferences

=cut

sub list_sysprefs {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $rs       = Koha::Config::SysPrefs->search;
        my $sysprefs = $c->objects->search_rs($rs);
        return $c->render( status => 200, openapi => $sysprefs );
    } catch {
        $c->unhandled_exception($_);
    };

}

1;
