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

use Test::More tests => 5;
use Test::Mojo;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;

use List::Util qw(min);

use Koha::Libraries;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
t::lib::Mocks::mock_preference( 'EnableVolumes', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'volumes list() tests' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 4 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->id;

    $t->get_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes" )
        ->status_is( 200, 'SWAGGER3.2.2' );
    my $response_count = scalar @{ $t->tx->res->json };
    is( $response_count, 0, 'Results count is 2');

    my $volume_1 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id, display_order => 1, description => "Vol 1" } )->store();

    $t->get_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes" )
        ->status_is( 200, 'SWAGGER3.2.2' );
    $response_count = scalar @{ $t->tx->res->json };
    is( $response_count, 1, 'Results count is 2');

    my $volume_2 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id, display_order => 2, description => "Vol 2" } )->store();

    $t->get_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes" )
      ->status_is( 200, 'SWAGGER3.2.2' );

    $response_count = scalar @{ $t->tx->res->json };
    is( $response_count, 2, 'Results count is 2');

    $schema->storage->txn_rollback;
};

subtest 'volumes add() tests' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $authorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $authorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $auth_userid = $authorized_patron->userid;

    my $unauthorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 0 }
    });
    $unauthorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $unauth_userid = $unauthorized_patron->userid;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->id;
    my $volume = { description => 'Vol 1', display_order => 1 };

    # Unauthorized attempt
    $t->post_ok( "//$unauth_userid:$password@/api/v1/biblios/$biblio_id/volumes" => json => $volume )
      ->status_is(403);

    # Authorized attempt
    $t->post_ok( "//$auth_userid:$password@/api/v1/biblios/$biblio_id/volumes" => json => $volume )
      ->status_is( 201, 'SWAGGER3.2.1' );

    # Invalid biblio id
    {   # hide useless warnings
        local *STDERR;
        open STDERR, '>', '/dev/null';
        $t->post_ok( "//$auth_userid:$password@/api/v1/biblios/XXX/volumes" => json => $volume )
            ->status_is( 404 );
        close STDERR;
    }

    $schema->storage->txn_rollback;
};

subtest 'volumes update() tests' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $authorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $authorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $auth_userid = $authorized_patron->userid;

    my $unauthorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 0 }
    });
    $unauthorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $unauth_userid = $unauthorized_patron->userid;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->id;
    my $volume = Koha::Biblio::Volume->new( { biblionumber => $biblio->id, display_order => 1, description => "Vol 1" } )->store();
    my $volume_id = $volume->id;

    # Unauthorized attempt
    $t->put_ok( "//$unauth_userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id"
                    => json => { description => 'New unauthorized desc change' } )
      ->status_is(403);

    # Authorized attempt
    $t->put_ok( "//$auth_userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id" => json => { description => "Vol A" } )
      ->status_is(200, 'SWAGGER3.2.1')
      ->json_has( '/description' => "Vol A", 'SWAGGER3.3.3' );

    # Invalid biblio id
    $t->put_ok( "//$auth_userid:$password@/api/v1/biblios/XXX/volumes/$volume_id" => json => { description => "Vol A" } )
        ->status_is(404);

    # Invalid volume id
    $t->put_ok( "//$auth_userid:$password@/api/v1/biblios/$biblio_id/volumes/XXX" => json => { description => "Vol A" } )
        ->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'volumes delete() tests' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;

    my $authorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $authorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $auth_userid = $authorized_patron->userid;

    my $unauthorized_patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 0 }
    });
    $unauthorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $unauth_userid = $unauthorized_patron->userid;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->id;
    my $volume = Koha::Biblio::Volume->new( { biblionumber => $biblio->id, display_order => 1, description => "Vol 1" } )->store();
    my $volume_id = $volume->id;

    $t->delete_ok( "//$auth_userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id" )
        ->status_is(204, 'SWAGGER3.2.4')
        ->content_is('', 'SWAGGER3.3.4');

    # Unauthorized attempt to delete
    $t->delete_ok( "//$unauth_userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id" )
      ->status_is(403);

    $t->delete_ok( "//$auth_userid:$password@/api/v1/biblios/XXX/volumes/$volume_id" )
      ->status_is(404);

    $t->delete_ok( "//$auth_userid:$password@/api/v1/biblios/$biblio_id/volumes/XXX" )
      ->status_is(404);

    $schema->storage->txn_rollback;
};

subtest 'volume items add() + delete() tests' => sub {
    plan tests => 14;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 4 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;

    my $biblio = $builder->build_sample_biblio();
    my $biblio_id = $biblio->id;

    my $volume = Koha::Biblio::Volume->new( { biblionumber => $biblio->id, display_order => 1, description => "Vol 1" } )->store();
    my $volume_id = $volume->id;

    my @items = $volume->items;
    is( scalar(@items), 0, 'Volume has no items');

    my $item_1 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    my $item_1_id = $item_1->id;

    $t->post_ok( "//$userid:$password@/api/v1/biblios/XXX/volumes/$volume_id/items" => json => { item_id => $item_1->id } )
      ->status_is( 409 )
      ->json_is( { error => 'Volume does not belong to passed biblio_id' } );

    $t->post_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id/items" => json => { item_id => $item_1->id } )
      ->status_is( 201, 'SWAGGER3.2.1' );

    @items = $volume->items;
    is( scalar(@items), 1, 'Volume now has one item');

    my $item_2 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    my $item_2_id = $item_2->id;

    $t->post_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id/items" => json => { item_id => $item_2->id } )
      ->status_is( 201, 'SWAGGER3.2.1' );

    @items = $volume->items;
    is( scalar(@items), 2, 'Volume now has two items');

    $t->delete_ok( "//$userid:$password@/api/v1/biblios/$biblio_id/volumes/$volume_id/items/$item_1_id" )
        ->status_is(204, 'SWAGGER3.2.4')
        ->content_is('', 'SWAGGER3.3.4');

    @items = $volume->items;
    is( scalar(@items), 1, 'Volume now has one item');

    $schema->storage->txn_rollback;
};
