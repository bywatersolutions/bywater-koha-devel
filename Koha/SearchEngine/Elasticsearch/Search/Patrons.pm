package Koha::SearchEngine::Elasticsearch::Search::Patrons;

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

use base qw(Koha::SearchEngine::Elasticsearch::Search);

use C4::Context;
use Koha::Patron::Attribute::Types;
use Koha::SearchEngine::Elasticsearch;

=head1 NAME

Koha::SearchEngine::Elasticsearch::Search::Patrons - Patron search via ES

=head1 SYNOPSIS

    use Koha::SearchEngine::Elasticsearch::Search::Patrons;

    my $searcher = Koha::SearchEngine::Elasticsearch::Search::Patrons->new();
    my $results  = $searcher->search_patrons(
        query    => "smith",
        page     => 1,
        per_page => 20,
        order_by => "-surname",
        filters  => { branchcode => "CPL" },
        library  => $logged_in_library,
    );

=cut

# Core fields always included in search
my @CORE_SEARCH_FIELDS = qw(
    patron_name surname firstname cardnumber userid
    email emailpro B_email phone mobile
    address address2 city state postal_code
);

# Fields used for facet aggregations
my @FACET_FIELDS = qw( library_id category_id restricted );

sub new {
    my ( $class, $params ) = @_;
    $params //= {};
    $params->{index} = $Koha::SearchEngine::Elasticsearch::PATRONS_INDEX;
    return $class->SUPER::new($params);
}

=head2 search_patrons

    my $results = $searcher->search_patrons(
        query    => $q,
        fields   => \@fields,       # optional, overrides default
        page     => $page,
        per_page => $per_page,
        order_by => $order_by,       # e.g. "-surname", "+ext_attr_DEPT"
        filters  => \%filters,       # facet filters
        library  => $branchcode,     # caller's library for scoping
    );

Returns hashref: { total => $n, hits => \@patron_ids, facets => \%facets }

=cut

sub search_patrons {
    my ( $self, %args ) = @_;

    my $query_string = $args{query};
    my $page         = $args{page} // 1;
    my $per_page     = $args{per_page} // 20;
    my $order_by     = $args{order_by};
    my $filters      = $args{filters} // {};
    my $library      = $args{library};
    my $fields       = $args{fields};

    # Resolve search fields
    my @search_fields = $fields ? @$fields : $self->_resolve_search_fields($library);

    # Build the query body
    my $body = $self->_build_query(
        query_string  => $query_string,
        search_fields => \@search_fields,
        filters       => $filters,
        library       => $library,
    );

    # Sorting
    if ($order_by) {
        $body->{sort} = $self->_build_sort($order_by);
    }

    # Pagination
    $body->{from} = ( $page - 1 ) * $per_page;
    $body->{size} = $per_page;

    # Return only computed fields from _source (rest hydrated from DB)
    $body->{_source} = [qw( checkouts_count account_balance )];

    # Execute
    my $elasticsearch = $self->get_elasticsearch();
    my $response      = $elasticsearch->search(
        index            => $self->index_name,
        track_total_hits => \1,
        body             => $body,
    );

    # Parse results
    my $total = ref $response->{hits}{total} eq 'HASH'
        ? $response->{hits}{total}{value}
        : $response->{hits}{total};

    my @patron_ids = map { $_->{_id} } @{ $response->{hits}{hits} };

    # Extract _source fields keyed by patron_id
    my %es_data;
    for my $hit ( @{ $response->{hits}{hits} } ) {
        $es_data{ $hit->{_id} } = $hit->{_source} // {};
    }

    my %facets;
    if ( my $aggs = $response->{aggregations} ) {
        for my $field (@FACET_FIELDS) {
            next unless $aggs->{$field};
            $facets{$field} = [
                map { { value => $_->{key}, count => $_->{doc_count} } }
                    @{ $aggs->{$field}{buckets} }
            ];
        }
    }

    return {
        total   => $total,
        hits    => \@patron_ids,
        es_data => \%es_data,
        facets  => \%facets,
    };
}

=head2 autocomplete

    my $suggestions = $searcher->autocomplete(
        query    => $prefix,
        per_page => 10,
        library  => $branchcode,
    );

Returns arrayref of patron_ids matching the completion suggest.

=cut

sub autocomplete {
    my ( $self, %args ) = @_;

    my $query    = $args{query};
    my $per_page = $args{per_page} // 10;
    my $library  = $args{library};

    my $body = {
        suggest => {
            patron_suggest => {
                prefix     => $query,
                completion => {
                    field => 'suggest',
                    size  => $per_page,
                },
            },
        },
        _source => \0,
    };

    my $elasticsearch = $self->get_elasticsearch();
    my $response      = $elasticsearch->search(
        index => $self->index_name,
        body  => $body,
    );

    my @patron_ids;
    if ( my $suggestions = $response->{suggest}{patron_suggest} ) {
        for my $entry (@$suggestions) {
            push @patron_ids, map { $_->{_id} } @{ $entry->{options} };
        }
    }

    return \@patron_ids;
}

=head2 _resolve_search_fields

Returns the list of ES fields to search based on the caller's library.
Includes core fields + extended attribute fields visible to the library.

=cut

sub _resolve_search_fields {
    my ( $self, $library ) = @_;

    my @fields = @CORE_SEARCH_FIELDS;

    # Add searchable extended attribute fields visible to this library
    my $attr_types_rs = Koha::Patron::Attribute::Types->search_with_library_limits(
        { staff_searchable => 1 }, {}, $library
    );

    while ( my $type = $attr_types_rs->next ) {
        push @fields, "ext_attr_" . $type->code;
    }

    return @fields;
}

=head2 _build_query

Builds the ES query body with multi_match + filters + aggregations.

=cut

sub _build_query {
    my ( $self, %args ) = @_;

    my $query_string  = $args{query_string};
    my $search_fields = $args{search_fields};
    my $filters       = $args{filters};
    my $library       = $args{library};

    # Main text query — combine query_string with prefix for short queries
    my $escaped = $query_string;
    $escaped =~ s/([\+\-\=\&\|\>\<\!\(\)\{\}\[\]\^"~\*\?\:\\\/])/\\$1/g;
    my $lc_query = lc($query_string);

    my $must = {
        bool => {
            should => [
                {
                    query_string => {
                        query            => "$escaped*",
                        fields           => $search_fields,
                        analyze_wildcard => \1,
                    },
                },
                { prefix => { 'cardnumber.ci_raw' => $lc_query } },
                { prefix => { 'patron_name.ci_raw' => $lc_query } },
                { prefix => { 'email.ci_raw' => $lc_query } },
            ],
            minimum_should_match => 1,
        },
    };

    # Filter clauses
    my @filter_clauses;

    # Facet filters from the request
    for my $field ( keys %$filters ) {
        next unless defined $filters->{$field};
        my $value = $filters->{$field};
        next if ref $value eq 'ARRAY' && !@$value;
        next if !ref $value && $value eq '';

        my $es_field;
        if ( $field eq 'restricted' ) {
            $es_field = $field;
        } elsif ( $field =~ /^ext_attr_/ ) {
            $es_field = "${field}.raw";
        } else {
            $es_field = "${field}.facet";
        }

        if ( ref $value eq 'ARRAY' ) {
            push @filter_clauses, { terms => { $es_field => $value } };
        } else {
            push @filter_clauses, { term => { $es_field => $value } };
        }
    }

    # Library scoping (IndependentBranches)
    if ( $library && C4::Context->preference('IndependentBranches') ) {
        push @filter_clauses, { term => { 'library_id.facet' => $library } };
    }

    my $body = {
        query => {
            bool => {
                must   => $must,
                filter => \@filter_clauses,
            },
        },
        aggs => {
            map { $_ => { terms => { field => $_ eq 'restricted' ? $_ : "${_}.facet", size => 50 } } }
                @FACET_FIELDS
        },
    };

    return $body;
}

=head2 _build_sort

Translates an _order_by string like "-surname" or "+ext_attr_DEPT" into ES sort.

=cut

sub _build_sort {
    my ( $self, $order_by ) = @_;

    my @sort;
    for my $field ( split /,/, $order_by ) {
        $field =~ s/^\s+|\s+$//g;
        next unless $field;

        my $direction = 'asc';
        if ( $field =~ s/^-// ) {
            $direction = 'desc';
        } elsif ( $field =~ s/^\+// ) {
            $direction = 'asc';
        }

        # Use the .sort sub-field for sortable fields
        my $sort_field = "${field}.sort";
        push @sort, { $sort_field => { order => $direction, unmapped_type => 'long' } };
    }

    return \@sort;
}

1;
