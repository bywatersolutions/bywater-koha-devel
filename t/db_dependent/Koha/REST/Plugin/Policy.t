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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 5;
use Test::Mojo;

use Digest::MD5 qw( md5_base64 );
use Encode      qw( encode );
use Mojo::JWT;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Dummy app for testing the plugin
use Mojolicious::Lite;

app->log->level('error');

plugin 'Koha::REST::Plugin::Policy';

# Route that attaches the policy for the logged-in user's branch
get '/checkin_policy' => sub {
    my $c = shift;
    $c->stash( 'koha.user' => $c->app->{_test_user} );
    $c->attach_module_policy('Checkin');
    $c->render( status => 200, json => { ok => 1 } );
};

# Route that attaches the policy for an explicitly passed library
get '/checkin_policy_lib/:library_id' => sub {
    my $c = shift;
    $c->stash( 'koha.user' => $c->app->{_test_user} );
    $c->attach_module_policy( 'Checkin', { library => $c->stash('library_id') } );
    $c->render( status => 200, json => { ok => 1 } );
};

# Route that requests an unknown module scope
get '/unknown_policy' => sub {
    my $c = shift;
    $c->stash( 'koha.user' => $c->app->{_test_user} );
    $c->attach_module_policy('NoSuchModuleScope');
    $c->render( status => 200, json => { ok => 1 } );
};

my $t = Test::Mojo->new;

my $jwt_re = qr/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

subtest 'attach_module_policy() attaches a signed JWT header' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object(
        { class => 'Koha::Patrons', value => { branchcode => $library->branchcode, flags => 1 } } );

    app->{_test_user} = $patron;

    $t->get_ok('/checkin_policy')
        ->status_is(200)
        ->header_like( 'X-Koha-Module-Policy' => $jwt_re, 'X-Koha-Module-Policy header is a JWT' );

    $schema->storage->txn_rollback;
};

subtest 'attach_module_policy() honours an explicit library' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my $user_library  = $builder->build_object( { class => 'Koha::Libraries' } );
    my $other_library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron        = $builder->build_object(
        { class => 'Koha::Patrons', value => { branchcode => $user_library->branchcode, flags => 1 } } );

    app->{_test_user} = $patron;

    $t->get_ok( '/checkin_policy_lib/' . $other_library->branchcode )
        ->status_is(200)
        ->header_like( 'X-Koha-Module-Policy' => $jwt_re, 'header attached for explicit library' );

    $schema->storage->txn_rollback;
};

subtest 'attach_module_policy() is silent for an unknown scope' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron =
        $builder->build_object( { class => 'Koha::Patrons', value => { branchcode => $library->branchcode } } );

    app->{_test_user} = $patron;

    my $tx = $t->get_ok('/unknown_policy')->status_is(200)->tx;
    is(
        $tx->res->headers->header('X-Koha-Module-Policy'),
        undef, 'No header attached when the module policy class does not exist'
    );

    $schema->storage->txn_rollback;
};

subtest 'the attached JWT carries the module policy claims' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    # Mock the config secret so the JWT signing/verification is predictable
    # and independent of the environment's koha-conf.xml.
    my $config_pass = 'test_jwt_secret';
    t::lib::Mocks::mock_config( 'pass', $config_pass );
    t::lib::Mocks::mock_preference( 'UseRecalls', 1 );

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object(
        { class => 'Koha::Patrons', value => { branchcode => $library->branchcode, flags => 1 } } );

    app->{_test_user} = $patron;

    $t->get_ok('/checkin_policy')->status_is(200);

    my $jwt    = $t->tx->res->headers->header('X-Koha-Module-Policy');
    my $secret = md5_base64( encode( 'UTF-8', $config_pass ) );
    my $claims = Mojo::JWT->new( secret => $secret )->decode($jwt);

    ok( exists $claims->{recalls_enabled}, 'JWT carries a module capability key' );
    is( $claims->{recalls_enabled}, 1, 'recalls_enabled reflects the UseRecalls preference' );

    $schema->storage->txn_rollback;
};
