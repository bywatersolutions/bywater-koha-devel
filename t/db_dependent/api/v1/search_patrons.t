#!/usr/bin/env perl

# Tests for /api/v1/search/patrons and /api/v1/search/patrons/autocomplete

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 4;
use Test::MockModule;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'search - syspref disabled' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 0 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**4 }    # borrowers flag
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons?q=smith")
        ->status_is( 400, 'Returns 400 when syspref disabled' );

    $schema->storage->txn_rollback;
};

subtest 'search - syspref enabled' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**4 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    # Mock the ES search to return the librarian's ID
    my $search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search::Patrons');
    $search_mock->mock( 'new', sub {
        return bless { index => 'patrons', index_name => 'koha_patrons' }, $_[0];
    });
    $search_mock->mock( 'search_patrons', sub {
        return {
            total  => 1,
            hits   => [ $librarian->borrowernumber ],
            facets => {
                branchcode   => [ { value => $librarian->branchcode, count => 1 } ],
                categorycode => [ { value => $librarian->categorycode, count => 1 } ],
            },
        };
    });

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons?q=test")
        ->status_is(200)
        ->json_is( '/total', 1 )
        ->json_is( '/hits/0/patron_id', $librarian->borrowernumber );

    $schema->storage->txn_rollback;
};

subtest 'autocomplete' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**4 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    # Mock autocomplete to return the librarian
    my $search_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Search::Patrons');
    $search_mock->mock( 'new', sub {
        return bless { index => 'patrons', index_name => 'koha_patrons' }, $_[0];
    });
    $search_mock->mock( 'autocomplete', sub {
        return [ $librarian->borrowernumber ];
    });

    $t->get_ok("//$userid:$password\@/api/v1/search/patrons/autocomplete?q=test")
        ->status_is(200)
        ->json_is( '/0/patron_id', $librarian->borrowernumber )
        ->json_is( '/0/surname', $librarian->surname );

    $schema->storage->txn_rollback;
};
