package Koha::REST::V1::Search::Patrons;

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

use C4::Context;
use Koha::Patrons;

use Try::Tiny qw( catch try );

=head1 NAME

Koha::REST::V1::Search::Patrons

=head1 API

=head2 Methods

=head3 search

Controller function for searching patrons via Elasticsearch

=cut

sub search {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $q        = $c->param('q');
        my $fields   = $c->param('fields');
        my $order_by = $c->param('_order_by');
        my $page     = $c->param('_page') // 1;
        my $per_page = $c->param('_per_page') // 20;

        # Facet filters
        my $branchcode   = $c->param('branchcode');
        my $categorycode = $c->param('categorycode');
        my $debarred     = $c->param('debarred');

        unless ( C4::Context->preference('ElasticsearchPatronSearch') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "ElasticsearchPatronSearch is not enabled" },
            );
        }

        # TODO: Implement ES search
        # 1. Resolve searchable fields based on caller's library
        # 2. Build multi_match query in bool.must
        # 3. Apply facet filters in bool.filter
        # 4. Add aggs for branchcode, categorycode, debarred
        # 5. Apply sorting
        # 6. Execute search
        # 7. Hydrate results from DB

        return $c->render(
            status  => 200,
            openapi => { total => 0, hits => [], facets => {} },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 autocomplete

Controller function for patron autocomplete via Elasticsearch completion suggester

=cut

sub autocomplete {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $q        = $c->param('q');
        my $per_page = $c->param('_per_page') // 10;

        unless ( C4::Context->preference('ElasticsearchPatronSearch') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "ElasticsearchPatronSearch is not enabled" },
            );
        }

        # TODO: Implement ES completion suggester
        # 1. Build suggest query
        # 2. Return lightweight patron summaries

        return $c->render(
            status  => 200,
            openapi => [],
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
