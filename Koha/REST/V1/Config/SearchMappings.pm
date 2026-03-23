package Koha::REST::V1::Config::SearchMappings;

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

use Koha::SearchEngine::Elasticsearch;

use Try::Tiny qw( catch try );
use Encode;
use YAML::XS;

=head1 API

=head2 Methods

=head3 get

Controller method to retrieve search field mappings

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $type     = $c->param('type');
        my $mappings = Koha::SearchEngine::Elasticsearch::raw_elasticsearch_mappings($type);

        $c->respond_to(
            yaml => {
                status => 200,
                format => 'yaml',
                text   => Encode::decode_utf8( YAML::XS::Dump($mappings) ),
            },
            any => {
                status  => 200,
                openapi => $mappings,
            }
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
