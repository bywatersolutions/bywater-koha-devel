package Koha::SearchEngine::Indexer::Patrons;

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

=head1 NAME

Koha::SearchEngine::Indexer::Patrons - Factory for patron indexer backends

=head1 SYNOPSIS

    use Koha::SearchEngine::Indexer::Patrons;
    my $indexer = Koha::SearchEngine::Indexer::Patrons->new();
    $indexer->index_patrons( \@patron_ids );

=head1 DESCRIPTION

Returns the appropriate patron indexer backend based on system preferences.
When ElasticsearchPatronSearch is enabled and SearchEngine is Elasticsearch,
returns the ES backend. Otherwise returns the Database backend.

=cut

use Modern::Perl;
use C4::Context;

sub new {
    my $class = shift;

    my $engine = C4::Context->preference('SearchEngine') // '';
    my $use_es = C4::Context->preference('ElasticsearchPatronSearch');

    my ( $file, $backend_class );
    if ( $engine eq 'Elasticsearch' && $use_es ) {
        $file          = 'Koha/SearchEngine/Elasticsearch/Indexer/Patrons.pm';
        $backend_class = 'Koha::SearchEngine::Elasticsearch::Indexer::Patrons';
    } else {
        $file          = 'Koha/SearchEngine/Database/Indexer/Patrons.pm';
        $backend_class = 'Koha::SearchEngine::Database::Indexer::Patrons';
    }

    require $file;
    return $backend_class->new(@_);
}

1;
