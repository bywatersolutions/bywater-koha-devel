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
    $csp->set_nonce();

    my $res = $self->app->($env);
    return $res unless $csp->is_enabled;

    return Plack::Util::response_cb(
        $res,
        sub {
            my $res                     = shift;
            my $headers                 = $res->[1];
            my $add_reporting_endpoints = 1;
            for ( my $i = 0 ; $i < @$headers ; $i++ ) {

                # if reporting-endpoints already exists, append it
                if ( lc( $headers->[$i] ) eq 'reporting-endpoints' ) {
                    $headers->[ $i + 1 ] = _add_csp_to_reporting_endpoints( $headers->[ $i + 1 ] );
                    $add_reporting_endpoints = 0;
                    last;
                }
            }

            # reporting-endpoints is not yet defined, so let's define it
            if ($add_reporting_endpoints) {
                push @$headers, ( 'Reporting-Endpoints' => _add_csp_to_reporting_endpoints() );
            }
            push @$headers, ( $csp->header_name => $csp->header_value );
        }
    );
}

sub _add_csp_to_reporting_endpoints {
    my ($value) = @_;
    if ( $value && $value =~ /^\w+/ ) {
        $value = $value . ', ';
    } else {
        $value = '';
    }
    $value = $value . 'csp-violations="/api/v1/public/csp-reports"';

    return $value;
}
1;
