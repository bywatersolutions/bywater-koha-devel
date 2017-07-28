#!/usr/bin/perl

# Copyright 2013, 2019, 2023 Koha Development team
#
# This file is part of Koha
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 4;
use Test::Exception;

use C4::Context;
use Koha::Database;
use Koha::Statistics;

use t::lib::TestBuilder;
use t::lib::Mocks;
use Test::MockModule;

our $schema  = Koha::Database->new->schema;
our $builder = t::lib::TestBuilder->new;

our $test_params = {    # No FK checks here
    branch         => "BRA",
    itemnumber     => 31,
    borrowernumber => 5,
    categorycode   => 'S',
    amount         => 5.1,
    other          => "bla",
    itemtype       => "BK",
    location       => "LOC",
    ccode          => "CODE",
    interface      => 'INTERFACE',
};

subtest 'Basic Koha object tests' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $item    = $builder->build_sample_item;
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );

    Koha::Statistic->new(
        {
            type           => 'issue',
            branch         => $library->branchcode,
            itemnumber     => $item->itemnumber,
            borrowernumber => $patron->borrowernumber,
            itemtype       => $item->effective_itemtype,
            location       => $item->location,
            ccode          => $item->ccode,
            interface      => C4::Context->interface,
        }
    )->store;

    my $stat = Koha::Statistics->search( { itemnumber => $item->itemnumber } )->next;
    is( $stat->borrowernumber,   $patron->borrowernumber, 'Patron is there' );
    is( $stat->branch,           $library->branchcode,    'Library is there' );
    is( ref( $stat->item ),      'Koha::Item',            '->item returns a Koha::Item object' );
    is( $stat->item->itemnumber, $item->itemnumber,       '->item works great' );

    $schema->storage->txn_rollback;
};

subtest 'Test exceptions in ->new' => sub {
    plan tests => 6;
    $schema->storage->txn_begin;

    throws_ok { Koha::Statistic->new } 'Koha::Exceptions::BadParameter', '->new called without params';

    #FIXME Should we remove this for sake of consistency?

    # Type is missing
    my $params = {%$test_params};
    throws_ok { Koha::Statistic->new($params) } 'Koha::Exceptions::WrongParameter', '->new called without type';

    # Type is not allowed
    $params = {%$test_params};
    $params->{type} = "bla";
    throws_ok { Koha::Statistic->new($params) } 'Koha::Exceptions::WrongParameter', '->new called with wrong type';

    # Test mandatory accounts/circulation keys
    $params = {%$test_params};
    $params->{type} = 'payment';
    delete $params->{amount};
    throws_ok { Koha::Statistic->new($params) } 'Koha::Exceptions::MissingParameter',
        '->new called for accounts without amount';
    $params->{amount} = 0;
    lives_ok { Koha::Statistic->new($params) } '->new accepts zero amount';
    $params->{type} = 'issue';
    delete $params->{itemnumber};
    throws_ok { Koha::Statistic->new($params) } 'Koha::Exceptions::MissingParameter',
        '->new called for circulation without itemnumber';

    $schema->storage->txn_rollback;
};

subtest 'Test new->store (fka UpdateStats)' => sub {
    plan tests => 15;
    $schema->storage->txn_begin;

    # save the params in the right database fields
    my $statistic = insert_and_fetch( { %$test_params, type => 'return' } );
    is( $statistic->branch,         $test_params->{branch},         "Check branch" );
    is( $statistic->type,           'return',                       "Check type" );
    is( $statistic->borrowernumber, $test_params->{borrowernumber}, "Check borrowernumber" );
    is( $statistic->value,          $test_params->{amount},         "Check value" );
    is( $statistic->other,          $test_params->{other},          "Check other" );
    is( $statistic->itemtype,       $test_params->{itemtype},       "Check itemtype" );
    is( $statistic->location,       $test_params->{location},       "Check location" );
    is( $statistic->ccode,          $test_params->{ccode},          "Check ccode" );
    is( $statistic->interface,      $test_params->{interface},      "Check interface" );

    # Test location with undef and empty string
    my $params = { %$test_params, type => 'return' };
    delete $params->{location};
    $statistic = insert_and_fetch($params);
    is( $statistic->location, undef, "Location is NULL if not passed" );
    $params->{location} = q{};
    $statistic = insert_and_fetch($params);
    is( $statistic->location, q{}, "Location is empty string if passed" );

    # Test 'other' with undef and empty string (slightly different behavior from location, using _key_or_default)
    $params = { %$test_params, type => 'return' };
    delete $params->{other};
    $statistic = insert_and_fetch($params);
    is( $statistic->other, q{}, "Other is empty string if not passed" );
    $params->{other} = undef;
    $statistic = insert_and_fetch($params);
    is( $statistic->other, undef, "Other is NULL if passed undef" );

    # Test amount versus value; value is the db column, amount is the legacy name (to be deprecated?)
    $params    = { %$test_params, type => 'return', value => 0 };
    $statistic = insert_and_fetch($params);
    is( $statistic->value, 0, "Value is zero, overriding non-zero amount" );
    delete $params->{value};
    $statistic = insert_and_fetch($params);
    is( $statistic->value, 5.1, "No value passed, amount used" );

    $schema->storage->txn_rollback;
};

sub insert_and_fetch {
    my $params    = shift;
    my $statistic = Koha::Statistic->new($params)->store;
    return Koha::Statistics->search( { borrowernumber => $test_params->{borrowernumber} } )->last;

    # FIXME discard_changes would be nicer, but we dont have a PK (yet)
}

subtest 'Log borrower cardnumbers and item barcodes which are not valid' => sub {
    plan tests => 10;
    $schema->storage->txn_begin;

    #my $builder    = t::lib::TestBuilder->new;
    my $library    = $builder->build( { source => 'Branch' } );
    my $branchcode = $library->{branchcode};
    my $context    = Test::MockModule->new('C4::Context');
    $context->mock(
        'userenv',
        sub {
            return {
                flags  => 1,
                id     => 'my_userid',
                branch => $branchcode,
                number => '-1',
            };
        }
    );

    # Test Koha::Statistic->log_invalid_patron
    my $dbh = $schema->storage->dbh;
    $dbh->do(q{DELETE FROM statistics});
    t::lib::Mocks::mock_preference( "LogInvalidPatrons", 0 );
    Koha::Statistics->log_invalid_patron( { patron => 'InvalidCardnumber' } );
    is(
        Koha::Statistics->search()->count(), 0,
        'No stat line added if system preference LogInvalidPatrons is disabled'
    );

    t::lib::Mocks::mock_preference( "LogInvalidPatrons", 1 );
    Koha::Statistics->log_invalid_patron( { patron => 'InvalidCardnumber' } );
    my $stat = Koha::Statistics->search()->next();
    is( $stat->type,           'invalid_patron',    'Type set to invalid_patron' );
    is( $stat->borrowernumber, '-1',                'Associated library id set correctly' );
    is( $stat->other,          'InvalidCardnumber', 'Invalid cardnumber is set correctly' );
    is( $stat->branch,         $branchcode,         'Branchcode is set correctly' );

    # Test Koha::Statistic->log_invalid_item
    $dbh->do(q{DELETE FROM statistics});
    t::lib::Mocks::mock_preference( "LogInvalidItems", 0 );
    Koha::Statistics->log_invalid_item( { item => 'InvalidBarcode' } );
    is( Koha::Statistics->search()->count(), 0, 'No stat line added if system preference LogInvalidItems is disabled' );

    t::lib::Mocks::mock_preference( "LogInvalidItems", 1 );
    Koha::Statistics->log_invalid_item( { item => 'InvalidBarcode' } );
    $stat = Koha::Statistics->search()->next();
    is( $stat->type,           'invalid_item',   'Type set to invalid_item' );
    is( $stat->borrowernumber, '-1',             'Associated library id set correctly' );
    is( $stat->other,          'InvalidBarcode', 'Invalid barcode is set correctly' );
    is( $stat->branch,         $branchcode,      'Branchcode is set correctly' );

    $schema->storage->txn_rollback;
};
