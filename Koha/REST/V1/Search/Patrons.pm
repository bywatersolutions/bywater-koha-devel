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

use Mojo::JSON;
use C4::Context;
use Koha::Patrons;
use Koha::SearchEngine::Elasticsearch::Search::Patrons;

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
        unless ( C4::Context->preference('ElasticsearchPatronSearch') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "ElasticsearchPatronSearch is not enabled" },
            );
        }

        my $q        = $c->param('q');
        my $fields   = $c->param('fields');
        my $order_by = $c->param('_order_by');
        my $page     = $c->param('_page') // 1;
        my $per_page = $c->param('_per_page') // 20;

        # Strip 'me.' prefix from _order_by (kohaTable adds it)
        if ($order_by) {
            $order_by =~ s/me\.//g;
        }

        # Facet filters (core fields + extended attributes)
        my %filters;
        for my $f (qw( branchcode categorycode debarred )) {
            my $val = $c->param($f);
            $filters{$f} = $val if defined $val;
        }
        # JSON filters param (supports ext_attr_{CODE} and others)
        if ( my $filters_json = $c->param('filters') ) {
            my $extra = eval { Mojo::JSON::decode_json($filters_json) } // {};
            %filters = ( %filters, %$extra );
        }

        my $library = $c->stash('koha.user')->branchcode;

        my $searcher = Koha::SearchEngine::Elasticsearch::Search::Patrons->new();
        my $results  = $searcher->search_patrons(
            query    => $q,
            fields   => $fields ? [ split /\|/, $fields ] : undef,
            page     => $page,
            per_page => $per_page,
            order_by => $order_by,
            filters  => \%filters,
            library  => $library,
        );

        # Hydrate patron objects from DB
        my @patrons;
        if ( @{ $results->{hits} } ) {
            my $patrons_rs = Koha::Patrons->search(
                { borrowernumber => { -in => $results->{hits} } }
            );
            # Preserve ES result order
            my %order = map { $results->{hits}[$_] => $_ } 0 .. $#{ $results->{hits} };
            @patrons = sort { $order{ $a->borrowernumber } <=> $order{ $b->borrowernumber } }
                $patrons_rs->as_list;
        }

        my $user = $c->stash('koha.user');

        # Response headers for kohaTable/DataTables compatibility
        $c->res->headers->add( 'X-Total-Count'      => $results->{total} );
        $c->res->headers->add( 'X-Base-Total-Count' => $results->{total} );
        if ( my $request_id = $c->req->headers->header('x-koha-request-id') ) {
            $c->res->headers->add( 'x-koha-request-id' => $request_id );
        }

        return $c->render(
            status  => 200,
            openapi => {
                total  => $results->{total},
                hits   => [ map { $_->to_api({ user => $user }) } @patrons ],
                facets => $results->{facets},
            },
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
        unless ( C4::Context->preference('ElasticsearchPatronSearch') ) {
            return $c->render(
                status  => 400,
                openapi => { error => "ElasticsearchPatronSearch is not enabled" },
            );
        }

        my $q        = $c->param('q');
        my $per_page = $c->param('_per_page') // 10;
        my $library  = $c->stash('koha.user')->branchcode;

        my $searcher   = Koha::SearchEngine::Elasticsearch::Search::Patrons->new();
        my $patron_ids = $searcher->autocomplete(
            query    => $q,
            per_page => $per_page,
            library  => $library,
        );

        my @suggestions;
        if (@$patron_ids) {
            my $patrons_rs = Koha::Patrons->search(
                { borrowernumber => { -in => $patron_ids } }
            );
            my %order = map { $patron_ids->[$_] => $_ } 0 .. $#$patron_ids;
            my @sorted = sort { $order{ $a->borrowernumber } <=> $order{ $b->borrowernumber } }
                $patrons_rs->as_list;

            @suggestions = map {
                {
                    patron_id   => $_->borrowernumber,
                    cardnumber  => $_->cardnumber,
                    firstname   => $_->firstname,
                    surname     => $_->surname,
                    library_id  => $_->branchcode,
                    category_id => $_->categorycode,
                }
            } @sorted;
        }

        return $c->render(
            status  => 200,
            openapi => \@suggestions,
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
