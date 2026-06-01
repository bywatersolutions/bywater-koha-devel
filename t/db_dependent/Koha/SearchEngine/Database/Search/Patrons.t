#!/usr/bin/env perl

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

use Test::NoWarnings;
use Test::More tests => 7;

use t::lib::TestBuilder;
use t::lib::Mocks;

use C4::Context;
use Koha::Database;
use Koha::SearchEngine::Database::Indexer::Patrons;
use Koha::SearchEngine::Database::Search::Patrons;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;
my $dbh     = C4::Context->dbh;

# Ensure table exists
$dbh->do(q{
    CREATE TABLE IF NOT EXISTS patron_search_index (
        id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        patron_id       INT NOT NULL,
        field_group     VARCHAR(80) NOT NULL,
        content         MEDIUMTEXT NOT NULL,
        PRIMARY KEY (id),
        INDEX idx_psi_patron (patron_id),
        INDEX idx_psi_group_patron (field_group, patron_id),
        FULLTEXT INDEX idx_psi_ft (content)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
});

subtest 'index_patrons creates correct rows' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => {
                surname   => 'TestSurname',
                firstname => 'TestFirst',
                email     => 'test@example.com',
                cardnumber => 'TESTCARD001',
            }
        }
    );

    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron->borrowernumber ] );

    my $rows = $dbh->selectall_arrayref(
        "SELECT field_group, content FROM patron_search_index WHERE patron_id = ?",
        { Slice => {} }, $patron->borrowernumber
    );

    ok( scalar @$rows > 0, 'Rows created for patron' );

    my %by_group = map { $_->{field_group} => $_->{content} } @$rows;

    is( $by_group{surname}, 'TestSurname', 'surname field group indexed' );
    is( $by_group{cardnumber}, 'TESTCARD001', 'cardnumber field group indexed' );
    like( $by_group{standard}, qr/TestSurname/, 'standard group contains surname' );
    like( $by_group{all}, qr/test\@example\.com/, 'all group contains email' );

    $schema->storage->txn_rollback;
};

subtest 'delete_patrons removes all rows' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron->borrowernumber ] );

    my ($count) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM patron_search_index WHERE patron_id = ?",
        undef, $patron->borrowernumber
    );
    ok( $count > 0, 'Rows exist before delete' );

    $indexer->delete_patrons( [ $patron->borrowernumber ] );

    ($count) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM patron_search_index WHERE patron_id = ?",
        undef, $patron->borrowernumber
    );
    is( $count, 0, 'All rows removed after delete' );

    $schema->storage->txn_rollback;
};

subtest 'search_patrons starts_with' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $patron1 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Johnson', firstname => 'Alice' } }
    );
    my $patron2 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Smith', firstname => 'John' } }
    );

    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron1->borrowernumber, $patron2->borrowernumber ] );

    my $searcher = Koha::SearchEngine::Database::Search::Patrons->new();

    my $results = $searcher->search_patrons( query => 'john', match => 'starts_with' );
    ok( $results->{total} >= 2, 'starts_with "john" finds Johnson and John' );

    $results = $searcher->search_patrons( query => 'smi', match => 'starts_with' );
    my @ids = @{ $results->{hits} };
    ok( ( grep { $_ == $patron2->borrowernumber } @ids ), 'starts_with "smi" finds Smith' );
    ok( !( grep { $_ == $patron1->borrowernumber } @ids ), 'starts_with "smi" does not find Johnson' );

    $schema->storage->txn_rollback;
};

subtest 'search_patrons contains' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $patron = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Williams', firstname => 'Robert' } }
    );

    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron->borrowernumber ] );

    # Commit so FULLTEXT index is visible (InnoDB requirement)
    $schema->storage->txn_commit;
    $schema->storage->txn_begin;

    my $searcher = Koha::SearchEngine::Database::Search::Patrons->new();

    my $results = $searcher->search_patrons( query => 'williams', match => 'contains' );
    ok( $results->{total} >= 1, 'contains "williams" finds the patron' );

    my @ids = @{ $results->{hits} };
    ok( ( grep { $_ == $patron->borrowernumber } @ids ), 'correct patron returned' );

    # Cleanup
    $indexer->delete_patrons( [ $patron->borrowernumber ] );
    $schema->storage->txn_rollback;
};

subtest 'search_patrons with category filter' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $cat1 = $builder->build_object( { class => 'Koha::Patron::Categories' } );
    my $cat2 = $builder->build_object( { class => 'Koha::Patron::Categories' } );

    my $patron1 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Findme', categorycode => $cat1->categorycode } }
    );
    my $patron2 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Findme', categorycode => $cat2->categorycode } }
    );

    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron1->borrowernumber, $patron2->borrowernumber ] );

    my $searcher = Koha::SearchEngine::Database::Search::Patrons->new();

    my $results = $searcher->search_patrons(
        query   => 'findme',
        match   => 'starts_with',
        filters => { category_id => $cat1->categorycode },
    );

    is( $results->{total}, 1, 'category filter returns 1 result' );
    is( $results->{hits}[0], $patron1->borrowernumber, 'correct patron returned with category filter' );

    $schema->storage->txn_rollback;
};

subtest 'search_patrons with library scoping' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;
    $dbh->do("DELETE FROM patron_search_index");

    my $lib1 = $builder->build_object( { class => 'Koha::Libraries' } );
    my $lib2 = $builder->build_object( { class => 'Koha::Libraries' } );

    my $patron1 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Scoped', branchcode => $lib1->branchcode } }
    );
    my $patron2 = $builder->build_object(
        { class => 'Koha::Patrons', value => { surname => 'Scoped', branchcode => $lib2->branchcode } }
    );

    my $indexer = Koha::SearchEngine::Database::Indexer::Patrons->new();
    $indexer->index_patrons( [ $patron1->borrowernumber, $patron2->borrowernumber ] );

    my $searcher = Koha::SearchEngine::Database::Search::Patrons->new();

    my $results = $searcher->search_patrons(
        query                => 'scoped',
        match                => 'starts_with',
        restricted_libraries => [ $lib1->branchcode ],
    );

    is( $results->{total}, 1, 'library scoping returns 1 result' );
    is( $results->{hits}[0], $patron1->borrowernumber, 'correct patron returned with library scoping' );

    $schema->storage->txn_rollback;
};
