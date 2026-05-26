#!/usr/bin/env perl

# Tests for ES indexing hooks in Koha::Patron and Koha::Patron::Attribute

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 3;
use Test::MockModule;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;
use Koha::Patrons;
use Koha::Patron::Attributes;
use Koha::Patron::Attribute::Types;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Track indexer calls
my @indexed_ids;
my @deleted_ids;

my $indexer_mock = Test::MockModule->new('Koha::SearchEngine::Elasticsearch::Indexer::Patrons');
$indexer_mock->mock( 'new',            sub { bless {}, $_[0] } );
$indexer_mock->mock( 'index_patrons',  sub { push @indexed_ids, @{ $_[1] } } );
$indexer_mock->mock( 'delete_patrons', sub { push @deleted_ids, @{ $_[1] } } );

my $job_mock = Test::MockModule->new('Koha::BackgroundJob::UpdateElasticPatronIndex');
$job_mock->mock( 'enqueue', sub { my ( $self, $args ) = @_; push @indexed_ids, @{ $args->{patron_ids} } } );

subtest 'Patron store/delete/anonymize hooks' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );
    t::lib::Mocks::mock_preference( 'BorrowersLog',              0 );

    @indexed_ids = ();
    @deleted_ids = ();

    # Create patron triggers index
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $id     = $patron->borrowernumber;
    $patron->store;

    ok( scalar( grep { $_ == $id } @indexed_ids ), 'Patron store triggers index_patrons' );

    # Update patron triggers reindex
    @indexed_ids = ();
    $patron->surname('NewSurname')->store;
    ok( scalar( grep { $_ == $id } @indexed_ids ), 'Patron update triggers reindex' );

    # Delete patron triggers delete from index
    @deleted_ids = ();
    $patron->delete;
    ok( scalar( grep { $_ == $id } @deleted_ids ), 'Patron delete triggers delete_patrons' );

    # Anonymize triggers delete from index
    my $patron2 = $builder->build_object( { class => 'Koha::Patrons' } );
    my $id2     = $patron2->borrowernumber;
    @deleted_ids = ();
    $patron2->anonymize;
    ok( scalar( grep { $_ == $id2 } @deleted_ids ), 'Patron anonymize triggers delete_patrons' );

    # Disabled syspref = no calls
    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 0 );
    @indexed_ids = ();
    @deleted_ids = ();

    my $patron3 = $builder->build_object( { class => 'Koha::Patrons' } );
    is( scalar @indexed_ids, 0, 'No indexing when syspref disabled (store)' );

    $patron3->surname('Another')->store;
    is( scalar @indexed_ids, 0, 'No indexing when syspref disabled (update)' );

    $patron3->delete;
    is( scalar @deleted_ids, 0, 'No deletion when syspref disabled' );

    $schema->storage->txn_rollback;
};

subtest 'Patron::Attribute store/delete hooks' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'ElasticsearchPatronSearch', 1 );
    t::lib::Mocks::mock_preference( 'BorrowersLog',              0 );

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $id     = $patron->borrowernumber;

    my $attr_type = $builder->build_object(
        {
            class => 'Koha::Patron::Attribute::Types',
            value => {
                repeatable    => 0,
                unique_id     => 0,
                category_code => undef,
                class         => '',
            }
        }
    );

    # Attribute store triggers patron reindex
    @indexed_ids = ();
    my $attr = Koha::Patron::Attribute->new(
        {
            borrowernumber => $id,
            code           => $attr_type->code,
            attribute      => 'test_value',
        }
    )->store;

    ok( scalar( grep { $_ == $id } @indexed_ids ), 'Attribute store triggers patron reindex' );

    # Attribute delete triggers patron reindex
    @indexed_ids = ();
    $attr->delete;
    ok( scalar( grep { $_ == $id } @indexed_ids ), 'Attribute delete triggers patron reindex' );

    $schema->storage->txn_rollback;
};
