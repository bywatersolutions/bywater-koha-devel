#!/usr/bin/perl

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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use utf8;

use Test::More tests => 4;
use Test::MockModule;

use t::lib::Mocks;
use t::lib::TestBuilder;

use MARC::Record;

use_ok('Koha::Acquisition::Utils');

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;
my $builder = t::lib::TestBuilder->new;
my $dbh = C4::Context->dbh;

subtest "get_infos_syspref" => sub {
    plan tests => 4;

    my $record = MARC::Record->new;
    $record->append_fields(
        MARC::Field->new( '500', '', '', a => 'Test 1' ),
        MARC::Field->new( '505', '', '', a => 'Test 2', u => 'http://example.com' ),
        MARC::Field->new( '520', '', '', a => 'Test 3' ),
        MARC::Field->new( '541', '', '', a => 'Test 4' ),
    );

    my $MarcFieldsToOrder = q{
test1: 500$a
test2: 505$a
test3: 520$a
test4: 541$a
    };
    t::lib::Mocks::mock_preference('MarcFieldsToOrder', $MarcFieldsToOrder);
    my $data = Koha::Acquisition::Utils::get_infos_syspref(
        'MarcFieldsToOrder',
        $record,
        [ 'test1', 'test2', 'test3', 'test4' ]
    );

    is( $data->{test1}, "Test 1", "Got test 1 correctly" );
    is( $data->{test2}, "Test 2", "Got test 2 correctly" );
    is( $data->{test3}, "Test 3", "Got test 3 correctly" );
    is( $data->{test4}, "Test 4", "Got test 4 correctly" );
};

subtest "get_infos_syspref_on_item" => sub {
    plan tests => 13;

    my $record = MARC::Record->new;
    $record->append_fields(
        MARC::Field->new( '500', '', '', a => 'Test 1' ),
        MARC::Field->new( '505', '', '', a => 'Test 2', u => 'http://example.com' ),
        MARC::Field->new( '975', '', '', a => 'Test 3', b => "Test 4" ),
        MARC::Field->new( '975', '', '', a => 'Test 5', b => "Test 6" ),
        MARC::Field->new( '975', '', '', a => 'Test 7', b => "Test 8" ),
        MARC::Field->new( '976', '', '', a => 'Test 9', b => "Test 10" ),
        MARC::Field->new( '976', '', '', a => 'Test 11', b => "Test 12" ),
        MARC::Field->new( '976', '', '', a => 'Test 13', b => "Test 14" ),
    );

    my $MarcItemFieldsToOrder = q{
testA: 975$a
testB: 975$b
testC: 976$a
testD: 976$b
    };
    t::lib::Mocks::mock_preference('MarcItemFieldsToOrder', $MarcItemFieldsToOrder);
    my $data = Koha::Acquisition::Utils::get_infos_syspref_on_item(
        'MarcItemFieldsToOrder',
        $record,
        [ 'testA', 'testB', 'testC', 'testD' ]
    );

    is( $data->[0]->{testA}, "Test 3", 'Got first 975$a correctly' );
    is( $data->[0]->{testB}, "Test 4", 'Got first 975$b correctly' );
    is( $data->[1]->{testA}, "Test 5", 'Got second 975$a correctly' );
    is( $data->[1]->{testB}, "Test 6", 'Got second 975$b correctly' );
    is( $data->[2]->{testA}, "Test 7", 'Got third 975$a correctly' );
    is( $data->[2]->{testB}, "Test 8", 'Got third 975$b correctly' );

    is( $data->[0]->{testC}, "Test 9", 'Got first 976$a correctly' );
    is( $data->[0]->{testD}, "Test 10", 'Got first 976$b correctly' );
    is( $data->[1]->{testC}, "Test 11", 'Got second 976$a correctly' );
    is( $data->[1]->{testD}, "Test 12", 'Got second 976$b correctly' );
    is( $data->[2]->{testC}, "Test 13", 'Got third 976$a correctly' );
    is( $data->[2]->{testD}, "Test 14", 'Got third 976$b correctly' );

    # Test with bad record where fields are not one-to-one
    $record->append_fields(
        MARC::Field->new( '500', '', '', a => 'Test 1' ),
        MARC::Field->new( '505', '', '', a => 'Test 2', u => 'http://example.com' ),
        MARC::Field->new( '975', '', '', a => 'Test 3', b => "Test 4" ),
        MARC::Field->new( '975', '', '', b => "Test 6" ),
        MARC::Field->new( '975', '', '', b => 'Test 7' ),
        MARC::Field->new( '976', '', '', a => 'Test 9', b => "Test 10" ),
        MARC::Field->new( '976', '', '', a => 'Test 11', b => "Test 12" ),
    );

    $data = Koha::Acquisition::Utils::get_infos_syspref_on_item(
        'MarcItemFieldsToOrder',
        $record,
        [ 'testA', 'testB', 'testC', 'testD' ]
    );
    is( $data, -1, "Got -1 if record fields are not one-to-one");
};

subtest "equal_number_of_fields" => sub {
    plan tests => 2;

    my $record = MARC::Record->new;
    $record->append_fields(
        MARC::Field->new( '500', '', '', a => 'Test 1' ),
        MARC::Field->new( '505', '', '', a => 'Test 2', u => 'http://example.com' ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '976', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '976', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '976', '', '', a => 'Test a', b => "Test b" ),
    );

    my $data = Koha::Acquisition::Utils::equal_number_of_fields( [ '975', '976' ], $record );
    is( $data, '3', "Got correct number of fields in return value" );

    # Test with non-matching field sets
    $record->append_fields(
        MARC::Field->new( '500', '', '', a => 'Test 1' ),
        MARC::Field->new( '505', '', '', a => 'Test 2', u => 'http://example.com' ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '975', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '976', '', '', a => 'Test a', b => "Test b" ),
        MARC::Field->new( '976', '', '', a => 'Test a', b => "Test b" ),
    );

    $data = Koha::Acquisition::Utils::equal_number_of_fields( [ '975', '976' ], $record );
    is( $data, '-1', "Got -1 in return value" );
};

$schema->storage->txn_rollback;
C4::Context->clear_syspref_cache();
