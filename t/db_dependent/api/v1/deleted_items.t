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
use Test::More tests => 4;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Items;
use Koha::Old::Items;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'list() tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    Koha::Old::Items->search->delete;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**2 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $unauth_userid = $patron->userid;

    $t->get_ok("//$userid:$password@/api/v1/deleted/items")->status_is(200)->json_is( [] );

    my $item         = $builder->build_sample_item();
    my $item_id      = $item->itemnumber;
    my $item_data    = $item->unblessed;
    my $deleted_item = Koha::Old::Item->new($item_data)->store;
    $item->delete;

    $t->get_ok("//$userid:$password@/api/v1/deleted/items")->status_is(200);

    my $expected = $deleted_item->to_api;

    $t->json_has('/0')->json_is( '/0' => $expected );

    $t->get_ok("//$unauth_userid:$password@/api/v1/deleted/items")->status_is(403);

    $schema->storage->txn_rollback;
};

subtest 'get() tests' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $item         = $builder->build_sample_item();
    my $item_id      = $item->itemnumber;
    my $item_data    = $item->unblessed;
    my $deleted_item = Koha::Old::Item->new($item_data)->store;
    $item->delete;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2**2 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $unauth_userid = $patron->userid;

    $t->get_ok("//$userid:$password@/api/v1/deleted/items/$item_id")->status_is(200)->json_is( $deleted_item->to_api );

    $t->get_ok("//$unauth_userid:$password@/api/v1/deleted/items/$item_id")->status_is(403);

    my $non_existent_id = $item_id + 99999;

    $t->get_ok("//$userid:$password@/api/v1/deleted/items/$non_existent_id")->status_is(404)
        ->json_is( '/error' => 'Item not found' );

    $schema->storage->txn_rollback;
};

subtest 'restore() tests' => sub {

    plan tests => 15;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $librarian->borrowernumber,
                module_bit     => 13,
                code           => 'records_restore',
            }
        }
    );

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $unauth_userid = $patron->userid;

    my $item         = $builder->build_sample_item( { barcode => 'TEST_RESTORE_ITEM' } );
    my $item_id      = $item->itemnumber;
    my $item_data    = $item->unblessed;
    my $deleted_item = Koha::Old::Item->new($item_data)->store;
    $item->delete;

    is( Koha::Items->find($item_id), undef, 'Item deleted successfully' );
    ok( $deleted_item, 'Item found in deleted table' );

    $t->put_ok("//$unauth_userid:$password@/api/v1/deleted/items/$item_id")->status_is(403);

    $t->put_ok("//$userid:$password@/api/v1/deleted/items/$item_id")->status_is(200);

    my $restored_item = Koha::Items->find($item_id);
    ok( $restored_item, 'Item restored successfully' );
    is( $restored_item->barcode, 'TEST_RESTORE_ITEM', 'Item barcode preserved' );

    is( Koha::Old::Items->find($item_id), undef, 'Item removed from deleted table' );

    $t->put_ok("//$userid:$password@/api/v1/deleted/items/$item_id")->status_is(404);

    my $item_without_biblio = $builder->build_sample_item( { barcode => 'TEST_NO_BIBLIO' } );
    my $orphan_item_id      = $item_without_biblio->itemnumber;
    my $orphan_biblio_id    = $item_without_biblio->biblionumber;
    my $orphan_item_data    = $item_without_biblio->unblessed;
    my $deleted_orphan_item = Koha::Old::Item->new($orphan_item_data)->store;
    $item_without_biblio->delete;
    Koha::Biblios->find($orphan_biblio_id)->delete;

    $t->put_ok("//$userid:$password@/api/v1/deleted/items/$orphan_item_id")->status_is(409)->json_has('/error')
        ->json_like( '/error', qr/Bibliographic record not found/ );

    $schema->storage->txn_rollback;
};
