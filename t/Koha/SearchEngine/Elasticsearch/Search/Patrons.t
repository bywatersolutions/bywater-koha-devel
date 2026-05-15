#!/usr/bin/env perl

# Tests for Koha::SearchEngine::Elasticsearch::Search::Patrons

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 4;
use Test::MockModule;
use Test::MockObject;

use t::lib::Mocks;

# Mock the ES base class so we don't need a real connection
my $es_base_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch');
$es_base_mock->mock( 'new', sub {
    my ( $class, $params ) = @_;
    return bless {
        index      => $params->{index},
        index_name => 'koha_' . $params->{index},
    }, $class;
});

my $es_search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search');
$es_search_mock->mock( 'new', sub {
    my ( $class, $params ) = @_;
    return bless {
        index      => $params->{index},
        index_name => 'koha_' . $params->{index},
    }, $class;
});

use_ok('Koha::SearchEngine::Elasticsearch::Search::Patrons');

subtest '_build_query' => sub {
    plan tests => 6;

    t::lib::Mocks::mock_preference( 'IndependentBranches', 0 );

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    # Basic query with no filters
    my $body = $searcher->_build_query(
        query_string  => 'smith',
        search_fields => [qw( patron_name surname cardnumber )],
        filters       => {},
        library       => 'CPL',
    );

    is( $body->{query}{bool}{must}{multi_match}{query}, 'smith', 'query string passed through' );
    is_deeply(
        $body->{query}{bool}{must}{multi_match}{fields},
        [qw( patron_name surname cardnumber )],
        'search fields passed through'
    );
    is( $body->{query}{bool}{must}{multi_match}{type}, 'cross_fields', 'uses cross_fields' );
    is_deeply( $body->{query}{bool}{filter}, [], 'no filters when none provided' );

    # With facet filter
    $body = $searcher->_build_query(
        query_string  => 'john',
        search_fields => [qw( patron_name )],
        filters       => { branchcode => 'CPL', categorycode => 'PT' },
        library       => 'CPL',
    );

    is( scalar @{ $body->{query}{bool}{filter} }, 2, 'two filter clauses for two facets' );

    # Aggregations present
    ok( exists $body->{aggs}{branchcode}, 'branchcode aggregation present' );
};

subtest '_build_sort' => sub {
    plan tests => 4;

    my $searcher = bless { index => 'patrons', index_name => 'koha_patrons' },
        'Koha::SearchEngine::Elasticsearch::Search::Patrons';

    my $sort = $searcher->_build_sort('-surname');
    is( $sort->[0]{'surname.sort'}{order}, 'desc', 'descending with - prefix' );

    $sort = $searcher->_build_sort('+firstname');
    is( $sort->[0]{'firstname.sort'}{order}, 'asc', 'ascending with + prefix' );

    $sort = $searcher->_build_sort('cardnumber');
    is( $sort->[0]{'cardnumber.sort'}{order}, 'asc', 'ascending by default (no prefix)' );

    $sort = $searcher->_build_sort('-ext_attr_DEPT');
    is( $sort->[0]{'ext_attr_DEPT.sort'}{order}, 'desc', 'extended attribute sort field' );
};
