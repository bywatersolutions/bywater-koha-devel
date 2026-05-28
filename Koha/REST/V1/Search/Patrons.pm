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
use Koha::SearchEngine::Search::Patrons;

use Try::Tiny qw( catch try );

=head1 NAME

Koha::REST::V1::Search::Patrons

=head1 API

=head2 Methods

=head3 search

Controller function for searching patrons via the configured search backend.

=cut

sub search {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $q        = $c->param('q');
        my $fields   = $c->param('fields');
        my $order_by = $c->param('_order_by');
        my $match    = $c->param('_match')    // 'contains';
        my $page     = $c->param('_page')     // 1;
        my $per_page = $c->param('_per_page') // 20;

        # Strip 'me.' prefix from _order_by (kohaTable adds it)
        if ($order_by) {
            $order_by =~ s/me\.//g;
        }

        # Column-level field filters (additive)
        my $column_filters = {};
        my @known_fields   = qw( cardnumber surname firstname patron_name phone date_of_birth
            library_id category_id expiry_date staff_notes email address city );
        for my $f (@known_fields) {
            my $val = $c->param($f);
            $column_filters->{$f} = $val if defined $val && $val ne '';
        }

        # Facet filters
        my $filters = {};
        for my $f (qw( library_id category_id restricted )) {
            my $val = $c->param($f);
            $filters->{$f} = $val if defined $val;
        }

        # JSON filters param (supports ext_attr_{CODE} and colon-separated fields)
        if ( my $filters_json = $c->param('filters') ) {
            my $extra = eval { Mojo::JSON::decode_json($filters_json) } // {};
            for my $key ( keys %$extra ) {
                if ( $key =~ /^ext_attr_/ || $key =~ /:/ ) {
                    $column_filters->{$key} = $extra->{$key};
                } else {
                    $filters->{$key} = $extra->{$key};
                }
            }
        }

        my @restricted_libraries = $c->stash('koha.user')->libraries_where_can_see_patrons;

        my $searcher = Koha::SearchEngine::Search::Patrons->new();
        my $results  = $searcher->search_patrons(
            query                => $q,
            fields               => $fields ? [ split /\|/, $fields ] : undef,
            match                => $match,
            column_filters       => $column_filters,
            page                 => $page,
            per_page             => $per_page,
            order_by             => $order_by,
            filters              => $filters,
            restricted_libraries => \@restricted_libraries,
        );

        # Hydrate patron objects from DB
        my @patrons;
        if ( @{ $results->{hits} } ) {
            my $patrons_rs = Koha::Patrons->search( { borrowernumber => { -in => $results->{hits} } } );

            # Preserve search result order
            my $order = { map { $results->{hits}[$_] => $_ } 0 .. $#{ $results->{hits} } };
            @patrons = sort { ( $order->{ $a->borrowernumber } // 0 ) <=> ( $order->{ $b->borrowernumber } // 0 ) }
                $patrons_rs->as_list;
        }

        my $user       = $c->stash('koha.user');
        my $index_data = $results->{index_data} // {};

        # Response headers for kohaTable/DataTables compatibility
        $c->res->headers->add( 'X-Total-Count'      => $results->{total} );
        $c->res->headers->add( 'X-Base-Total-Count' => $results->{total} );
        if ( my $request_id = $c->req->headers->header('x-koha-request-id') ) {
            $c->res->headers->add( 'x-koha-request-id' => $request_id );
        }

        my @hits = map {
            my $api     = $_->to_api( { user => $user } );
            my $indexed = $index_data->{ $_->borrowernumber } // {};
            $api->{account_balance} = $indexed->{account_balance} // $_->account->balance + 0;
            $api->{checkouts_count} = $indexed->{checkouts_count} // $_->checkouts->count;
            $api->{library} = {
                library_id => $api->{library_id},
                name       => $indexed->{library_name} // $_->library->branchname,
            };
            $api;
        } @patrons;

        return $c->render(
            status  => 200,
            openapi => {
                total  => $results->{total},
                hits   => \@hits,
                facets => $results->{facets},
            },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
