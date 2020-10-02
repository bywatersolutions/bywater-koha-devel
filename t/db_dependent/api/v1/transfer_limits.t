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

use Test::More tests => 3;
use Test::Mojo;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;

use List::Util qw(min);

use Koha::Item::Transfer::Limits;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'list() tests' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    Koha::Item::Transfer::Limits->delete;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
        value => { flags => 1 }
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;

    my $limit = $builder->build_object({ class => 'Koha::Item::Transfer::Limits' });

    $t->get_ok( "//$userid:$password@/api/v1/transfer_limits" )
      ->status_is( 200, 'SWAGGER3.2.2' )
      ->json_is( [$limit->to_api] );

    $schema->storage->txn_rollback;
};

subtest 'add() tests' => sub {

    plan tests => 8;

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
        value => { flags => 4 }
    });
    $unauthorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $unauth_userid = $unauthorized_patron->userid;

    my $limit = $builder->build_object({ class => 'Koha::Item::Transfer::Limits' });
    my $limit_hashref = $limit->to_api;
    delete $limit_hashref->{limit_id};
    $limit->delete;

    # Unauthorized attempt to write
    $t->post_ok( "//$unauth_userid:$password@/api/v1/transfer_limits" => json => $limit_hashref )
      ->status_is(403);

    # Authorized attempt to write invalid data
    my $limit_with_invalid_field = {'invalid' => 'invalid'};

    $t->post_ok( "//$auth_userid:$password@/api/v1/transfer_limits" => json => $limit_with_invalid_field )
      ->status_is(400)
      ->json_is(
        "/errors" => [
            {
                message => "Properties not allowed: invalid.",
                path    => "/body"
            }
        ]
    );

    # Authorized attempt to write
    $t->post_ok( "//$auth_userid:$password@/api/v1/transfer_limits" => json => $limit_hashref )
      ->status_is( 201, 'SWAGGER3.2.1' )
      ->json_has( '' => $limit_hashref, 'SWAGGER3.3.1' );

    $schema->storage->txn_rollback;
};

subtest 'delete() tests' => sub {
    plan tests => 7;

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
        value => { flags => 4 }
    });
    $unauthorized_patron->set_password({ password => $password, skip_validation => 1 });
    my $unauth_userid = $unauthorized_patron->userid;

    my $limit = $builder->build_object({ class => 'Koha::Item::Transfer::Limits' });
    my $limit_id = $limit->id;

    # Unauthorized attempt to delete
    $t->delete_ok( "//$unauth_userid:$password@/api/v1/transfer_limits/$limit_id" )
      ->status_is(403);

    $t->delete_ok( "//$auth_userid:$password@/api/v1/transfer_limits/$limit_id" )
      ->status_is(204, 'SWAGGER3.2.4')
      ->content_is('', 'SWAGGER3.3.4');

    $t->delete_ok( "//$auth_userid:$password@/api/v1/transfer_limits/$limit_id" )
      ->status_is(404);

    $schema->storage->txn_rollback;
};
