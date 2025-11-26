package Koha::Middleware::ContentSecurityPolicy;

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

use parent qw(Plack::Middleware);
use Plack::Request;
use Plack::Response;

use Koha::ContentSecurityPolicy;

=head1 METHODS

=head2 call

This method is called for each request, and adds the Content-Security-Policy or
the Content-Security-Policy-Report-Only header based on your CSP configuration in
koha-conf.xml.

=cut

sub call {
    my ( $self, $env ) = @_;

    my $req = Plack::Request->new($env);

    my $csp = Koha::ContentSecurityPolicy->new;

    my $res = $self->app->($env);
    return $res unless $csp->is_enabled;

    return Plack::Util::response_cb(
        $res,
        sub {
            my $res     = shift;
            my $headers = $res->[1];
            push @$headers, ( $csp->header_name => $csp->header_value );
        }
    );
}

1;
