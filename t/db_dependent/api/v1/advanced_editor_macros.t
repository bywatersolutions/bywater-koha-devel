#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Test::More tests => 5;
use Test::Mojo;
use Test::Warn;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::AdvancedEditorMacros;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

$schema->storage->txn_begin;

subtest 'list() tests' => sub {
    plan tests => 8;


    my $patron_1 = $builder->build_object({
        class => 'Koha::Patrons',
    });
    my $patron_2 = $builder->build_object({
        class => 'Koha::Patrons',
    });
    my $password = 'thePassword123';
    $patron_1->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron_1->userid;

    # Create test context
    my $macro_1 = $builder->build_object({ class => 'Koha::AdvancedEditorMacros', value =>
        {
            name => 'Test1',
            macro => 'delete 100',
            borrowernumber => $patron_1->borrowernumber,
        }
    });
    my $macro_2 = $builder->build_object({ class => 'Koha::AdvancedEditorMacros', value =>
        {
            name => 'Test2',
            macro => 'delete 100',
            borrowernumber => $patron_1->borrowernumber,
            public => 1,
        }
    });
    my $macro_3 = $builder->build_object({ class => 'Koha::AdvancedEditorMacros', value =>
        {
            name => 'Test3',
            macro => 'delete 100',
            borrowernumber => $patron_1->borrowernumber,
        }
    });
    my $macro_4 = $builder->build_object({ class => 'Koha::AdvancedEditorMacros', value =>
        {
            name => 'Test4',
            macro => 'delete 100',
            borrowernumber => $patron_1->borrowernumber,
            public => 1,
        }
    });

    my $macros_index = Koha::AdvancedEditorMacros->search({ -or => { public => 1, borrowernumber => $patron_1->borrowernumber } })->count-1;
    ## Authorized user tests
    # Make sure we are returned with the correct amount of macros
    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros" )
      ->status_is( 200, 'SWAGGER3.2.2' )
      ->json_has('/' . $macros_index . '/macro_id')
      ->json_hasnt('/' . ($macros_index + 1) . '/macro_id');

    subtest 'query parameters' => sub {

        plan tests => 15;
        $t->get_ok("//$userid:$password@/api/v1/advancededitormacros?name=" . $macro_2->name)
          ->status_is(200)
          ->json_has( [ $macro_2 ] );
        $t->get_ok("//$userid:$password@/api/v1/advancededitormacros?name=" . $macro_3->name)
          ->status_is(200)
          ->json_has( [ ] );
        $t->get_ok("//$userid:$password@/api/v1/advancededitormacros?macro_text=delete 100")
          ->status_is(200)
          ->json_has( [ $macro_1, $macro_2, $macro_4 ] );
        $t->get_ok("//$userid:$password@/api/v1/advancededitormacros?patron_id=" . $patron_1->borrowernumber)
          ->status_is(200)
          ->json_has( [ $macro_1, $macro_2 ] );
        $t->get_ok("//$userid:$password@/api/v1/advancededitormacros?public=1")
          ->status_is(200)
          ->json_has( [ $macro_2, $macro_4 ] );
    };

    # Warn on unsupported query parameter
    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros?macro_blah=blah" )
      ->status_is(400)
      ->json_is( [{ path => '/query/macro_blah', message => 'Malformed query string'}] );

};

subtest 'get() tests' => sub {

    plan tests => 12;

    my $patron = $builder->build_object({
        class => 'Koha::Patrons',
    });
    my $password = 'thePassword123';
    $patron->set_password({ password => $password, skip_validation => 1 });
    my $userid = $patron->userid;

    my $macro_1 = $builder->build_object( { class => 'Koha::AdvancedEditorMacros', value => {
            public => 1,
        }
    });
    my $macro_2 = $builder->build_object( { class => 'Koha::AdvancedEditorMacros', value => {
            public => 0,
        }
    });
    my $macro_3 = $builder->build_object( { class => 'Koha::AdvancedEditorMacros', value => {
            borrowernumber => $patron->borrowernumber,
        }
    });

    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros/" . $macro_1->id )
      ->status_is( 200, 'SWAGGER3.2.2' )
      ->json_is( '' => Koha::REST::V1::AdvancedEditorMacro::_to_api( $macro_1->TO_JSON ), 'SWAGGER3.3.2' );

    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros/" . $macro_2->id )
      ->status_is( 403, 'SWAGGER3.2.2' )
      ->json_is( '/error' => 'You do not have permission to access this macro' );

    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros/" . $macro_3->id )
      ->status_is( 200, 'SWAGGER3.2.2' )
      ->json_is( '' => Koha::REST::V1::AdvancedEditorMacro::_to_api( $macro_3->TO_JSON ), 'SWAGGER3.3.2' );

    my $non_existent_code = $macro_1->id;
    $macro_1->delete;

    $t->get_ok( "//$userid:$password@/api/v1/advancededitormacros/" . $non_existent_code )
      ->status_is(404)
      ->json_is( '/error' => 'Macro not found' );

};

subtest 'add() tests' => sub {

    plan tests => 17;

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

    my $library_obj = $builder->build_object({ class => 'Koha::Libraries' });
    my $library     = Koha::REST::V1::Library::_to_api( $library_obj->TO_JSON );
    $library_obj->delete;

    # Unauthorized attempt to write
    $t->post_ok( "//$unauth_userid:$password@/api/v1/libraries" => json => $library )
      ->status_is(403);

    # Authorized attempt to write invalid data
    my $library_with_invalid_field = { %$library };
    $library_with_invalid_field->{'branchinvalid'} = 'Library invalid';

    $t->post_ok( "//$auth_userid:$password@/api/v1/libraries" => json => $library_with_invalid_field )
      ->status_is(400)
      ->json_is(
        "/errors" => [
            {
                message => "Properties not allowed: branchinvalid.",
                path    => "/body"
            }
        ]
    );

    # Authorized attempt to write
    $t->post_ok( "//$auth_userid:$password@/api/v1/libraries" => json => $library )
      ->status_is( 201, 'SWAGGER3.2.1' )
      ->json_is( '' => $library, 'SWAGGER3.3.1' )
      ->header_is( Location => '/api/v1/libraries/' . $library->{library_id}, 'SWAGGER3.4.1' );

    # save the library_id
    my $library_id = $library->{library_id};
    # Authorized attempt to create with null id
    $library->{library_id} = undef;

    $t->post_ok( "//$auth_userid:$password@/api/v1/libraries" => json => $library )
      ->status_is(400)
      ->json_has('/errors');

    # Authorized attempt to create with existing id
    $library->{library_id} = $library_id;

    warning_like {
        $t->post_ok( "//$auth_userid:$password@/api/v1/libraries" => json => $library )
          ->status_is(409)
          ->json_has( '/error' => "Fails when trying to add an existing library_id")
          ->json_is(  '/conflict', 'PRIMARY' ); } # WTF
        qr/^DBD::mysql::st execute failed: Duplicate entry '(.*)' for key 'PRIMARY'/;

};

subtest 'update() tests' => sub {
    plan tests => 13;

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

    my $library    = $builder->build_object({ class => 'Koha::Libraries' });
    my $library_id = $library->branchcode;

    # Unauthorized attempt to update
    $t->put_ok( "//$unauth_userid:$password@/api/v1/libraries/$library_id"
                    => json => { name => 'New unauthorized name change' } )
      ->status_is(403);

    # Attempt partial update on a PUT
    my $library_with_missing_field = {
        address1 => "New library address",
    };

    $t->put_ok( "//$auth_userid:$password@/api/v1/libraries/$library_id" => json => $library_with_missing_field )
      ->status_is(400)
      ->json_has( "/errors" =>
          [ { message => "Missing property.", path => "/body/address2" } ]
      );

    my $deleted_library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $library_with_updated_field = Koha::REST::V1::Library::_to_api( $deleted_library->TO_JSON );
    $library_with_updated_field->{library_id} = $library_id;
    $deleted_library->delete;

    $t->put_ok( "//$auth_userid:$password@/api/v1/libraries/$library_id" => json => $library_with_updated_field )
      ->status_is(200, 'SWAGGER3.2.1')
      ->json_is( '' => $library_with_updated_field, 'SWAGGER3.3.3' );

    # Authorized attempt to write invalid data
    my $library_with_invalid_field = { %$library_with_updated_field };
    $library_with_invalid_field->{'branchinvalid'} = 'Library invalid';

    $t->put_ok( "//$auth_userid:$password@/api/v1/libraries/$library_id" => json => $library_with_invalid_field )
      ->status_is(400)
      ->json_is(
        "/errors" => [
            {
                message => "Properties not allowed: branchinvalid.",
                path    => "/body"
            }
        ]
    );

    my $non_existent_code = 'nope'.int(rand(10000));
    $t->put_ok("//$auth_userid:$password@/api/v1/libraries/$non_existent_code" => json => $library_with_updated_field)
      ->status_is(404);

};

subtest 'delete() tests' => sub {
    plan tests => 7;

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

    my $library_id = $builder->build( { source => 'Branch' } )->{branchcode};

    # Unauthorized attempt to delete
    $t->delete_ok( "//$unauth_userid:$password@/api/v1/libraries/$library_id" )
      ->status_is(403);

    $t->delete_ok( "//$auth_userid:$password@/api/v1/libraries/$library_id" )
      ->status_is(204, 'SWAGGER3.2.4')
      ->content_is('', 'SWAGGER3.3.4');

    $t->delete_ok( "//$auth_userid:$password@/api/v1/libraries/$library_id" )
      ->status_is(404);

};

$schema->storage->txn_rollback;
