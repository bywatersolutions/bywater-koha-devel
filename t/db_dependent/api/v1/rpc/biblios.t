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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 1;
use Test::Mojo;

use C4::Biblio qw{ModBiblio};

use t::lib::Mocks;
use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'populate_empty_callnumbers() tests' => sub {

    plan tests => 30;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_sample_biblio();
    my $record = $biblio->record;

    my $cn = q{PA522};
    my $in = q{.M38 1993};

    $record->insert_fields_ordered( MARC::Field->new( '050', ' ', ' ', a => $cn, b => $in ) );

    my $expected_callnumber = $cn . $in;

    my $patron = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );

    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    my $biblio_id = $biblio->id;

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json =>
            { external_id => 'something' } )->status_is( 403, 'Not enough permissions to update an item' );

    # Add permissions
    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $patron->borrowernumber,
                module_bit     => 9,
                code           => 'edit_catalogue'
            }
        }
    );

    t::lib::Mocks::mock_preference( 'itemcallnumber', '' );

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 409, 'Wrong configuration' )->json_is( '/error_code', q{missing_configuration} );

    t::lib::Mocks::mock_preference( 'itemcallnumber', '050ab' );

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 409, 'Callnumber empty' )->json_is( '/error_code', q{callnumber_empty} );

    ModBiblio( $record, $biblio_id );

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 200, 'No items but request successful' )->json_is( '/updated_items_count', 0 );

    my $item_1 = $builder->build_sample_item( { biblionumber => $biblio->id, itemcallnumber => q{} } );
    my $item_2 = $builder->build_sample_item( { biblionumber => $biblio->id, itemcallnumber => q{} } );
    my $item_3 = $builder->build_sample_item( { biblionumber => $biblio->id, itemcallnumber => q{} } );
    my $item_4 = $builder->build_sample_item( { biblionumber => $biblio->id, itemcallnumber => q{someCallNumber} } );

    my $item1_id = $item_1->id;

    $t->post_ok(
        "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/$item1_id/populate_empty_callnumbers" => json => {} )
        ->status_is( 200, 'Item updated' )->json_is( '/updated_items_count', 1 )
        ->json_is( '/callnumber', $expected_callnumber );

    my @items_to_update = ( $item_2->id, $item_3->id );

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 200, 'Items updated' )->json_is( '/updated_items_count', 2 )
        ->json_is( '/callnumber', $expected_callnumber )->json_is( '/modified_item_ids', \@items_to_update );

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 200, 'Items updated' )->json_is( '/updated_items_count', 0 );

    $t->post_ok(
        "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/$item1_id/populate_empty_callnumbers" => json => {} )
        ->status_is( 200, 'Item updated' )->json_is( '/updated_items_count', 0 );

    $biblio->delete;

    $t->post_ok( "//$userid:$password@/api/v1/rpc/biblios/$biblio_id/items/populate_empty_callnumbers" => json => {} )
        ->status_is( 404, 'Record not found' )->json_is( '/error' => q{Bibliographic record not found} )
        ->json_is( '/error_code' => q{not_found} );

    $schema->storage->txn_rollback;
};
