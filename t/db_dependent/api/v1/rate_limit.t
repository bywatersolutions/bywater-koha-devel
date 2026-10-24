#!/usr/bin/perl

# Copyright 2026 ByWater Solutions
#
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
use Test::More tests => 12;
use Test::MockModule;
use Test::Mojo;

use t::lib::Mocks;
use t::lib::Mocks::Logger;
use t::lib::Mocks::Memcached;
use t::lib::TestBuilder;

use C4::Auth qw( get_session );
use Koha::ApiKey;
use Koha::Database;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'SessionStorage', 'tmp' );

# startup reads the config, so it has to be mocked before the app exists
t::lib::Mocks::mock_config( 'api_rate_limit', undef );
my $t = Test::Mojo->new('Koha::REST::V1');

# and the logger mock has to come after it, or startup would store the mock as the app log
my $logger = t::lib::Mocks::Logger->new;

my $memcached;
my $counter_mock = Test::MockModule->new('Koha::RateLimit::Counter');
$counter_mock->mock( memcached => sub { return $memcached } );

my $client_ip   = '127.0.0.1';
my $plugin_mock = Test::MockModule->new('Koha::REST::Plugin::RateLimit');
$plugin_mock->mock( client_ip => sub { return $client_ip } );

# Fresh config and fresh counters for a subtest
sub limiter {
    my (%config) = @_;
    t::lib::Mocks::mock_config(
        'api_rate_limit',
        { enabled => 1, exempt_ips => q{}, token_limit => 0, %config }
    );
    $t->app->api_rate_limit->configure;
    $memcached = t::lib::Mocks::Memcached->new;
    $logger->clear;
    $t->ua->cookie_jar->empty;
    $client_ip = '127.0.0.1';
    return;
}

sub superlibrarian {
    my $patron   = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 1 } } );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    return ( $patron, $patron->userid, $password );
}

sub bearer_token {
    my ($patron) = @_;
    my $api_key = Koha::ApiKey->new( { patron_id => $patron->id, description => 'rate limit test' } )->store;
    $t->post_ok(
        '/api/v1/oauth/token',
        form => {
            grant_type    => 'client_credentials',
            client_id     => $api_key->client_id,
            client_secret => $api_key->plain_text_secret
        }
    )->status_is(200);
    return ( $api_key, $t->tx->res->json->{access_token} );
}

sub bearer_get {
    my ( $path, $token ) = @_;
    my $tx = $t->ua->build_tx( GET => $path );
    $tx->req->headers->authorization("Bearer $token");
    return $t->request_ok($tx);
}

sub session_get {
    my ( $path, $session_id ) = @_;
    my $tx = $t->ua->build_tx( GET => $path );
    $tx->req->cookies( { name => 'CGISESSID', value => $session_id } );
    return $t->request_ok($tx);
}

sub session_for {
    my ($patron) = @_;
    my $session = C4::Auth::get_session('');
    $session->param( 'number',   $patron->borrowernumber ) if $patron;
    $session->param( 'id',       $patron->userid )         if $patron;
    $session->param( 'ip',       '127.0.0.1' );
    $session->param( 'lasttime', time() );
    $session->flush;
    return $session->id;
}

subtest 'disabled passthrough' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
    my ( $patron, $userid, $password ) = superlibrarian();

    t::lib::Mocks::mock_config( 'api_rate_limit', undef );
    $t->app->api_rate_limit->configure;
    $memcached = t::lib::Mocks::Memcached->new;

    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(200) for 1 .. 3;
    is( scalar keys %{ $memcached->{store} }, 0, 'nothing is counted while disabled' );

    $schema->storage->txn_rollback;
};

subtest 'oauth class, one budget per API key' => sub {
    plan tests => 17;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTOAuth2ClientCredentials', 1 );
    limiter( oauth_limit => 2 );

    my ( $patron, undef, undef ) = superlibrarian();
    my ( $api_key_a, $token_a ) = bearer_token($patron);
    my ( $api_key_b, $token_b ) = bearer_token($patron);

    bearer_get( '/api/v1/libraries', $token_a )->status_is(200);
    bearer_get( '/api/v1/libraries', $token_a )->status_is(200);
    bearer_get( '/api/v1/libraries', $token_a )
        ->status_is(429)
        ->header_is( 'Retry-After' => 60 )
        ->json_is( '/error'      => 'Too many requests' )
        ->json_is( '/error_code' => 'rate_limited' );

    my $client_id = $api_key_a->client_id;
    $logger->warn_like(
        qr/^api_rate_limit event=limited mode=enforce class=oauth id=\Q$client_id\E ip=127\.0\.0\.1 method=GET path=\/api\/v1\/libraries n=3 limit=2$/,
        'the refusal is logged with the client id'
    )->clear;

    bearer_get( '/api/v1/libraries', $token_b )->status_is( 200, 'another key has its own budget' );
    ok( exists $memcached->{store}{"api_rl:oauth:$client_id"}, 'counted under the client id' );

    $schema->storage->txn_rollback;
};

subtest 'basic class, one budget per patron' => sub {
    plan tests => 9;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
    limiter( basic_limit => 2 );

    my ( $patron_a, $userid_a, $password_a ) = superlibrarian();
    my ( $patron_b, $userid_b, $password_b ) = superlibrarian();

    $t->get_ok("//$userid_a:$password_a@/api/v1/libraries")->status_is(200) for 1 .. 2;
    $t->get_ok("//$userid_a:$password_a@/api/v1/libraries")->status_is(429);
    $t->get_ok("//$userid_b:$password_b@/api/v1/libraries")->status_is( 200, 'another patron has its own budget' );
    ok( exists $memcached->{store}{ 'api_rl:basic:' . $patron_a->borrowernumber }, 'counted under the borrowernumber' );

    $schema->storage->txn_rollback;
};

subtest 'session class, one budget per logged-in session' => sub {
    plan tests => 11;

    $schema->storage->txn_begin;
    limiter( session_limit => 2 );

    my ( $patron, undef, undef ) = superlibrarian();
    my $session_a = session_for($patron);
    my $session_b = session_for($patron);

    session_get( '/api/v1/libraries', $session_a )->status_is(200) for 1 .. 2;
    session_get( '/api/v1/libraries', $session_a )->status_is(429);
    session_get( '/api/v1/libraries', $session_b )
        ->status_is( 200, 'a second session of the same patron has its own budget' );

    my @keys = keys %{ $memcached->{store} };
    is( scalar @keys, 2, 'two session counters' );
    like( $keys[0], qr/^api_rl:session:[0-9a-f]{16}$/, 'the key is a hash prefix' );
    ok( !grep( { /\Q$session_a\E|\Q$session_b\E/ } @keys ), 'the session id itself is never a key' );

    $schema->storage->txn_rollback;
};

subtest 'anonymous class, per anonymous session or per address' => sub {
    plan tests => 12;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTPublicAPI',               1 );
    t::lib::Mocks::mock_preference( 'RESTPublicAnonymousRequests', 1 );
    limiter( anonymous_limit => 2 );

    $t->get_ok('/api/v1/public/libraries')->status_is(200) for 1 .. 2;
    $t->get_ok('/api/v1/public/libraries')->status_is( 429, 'no session: limited per address' );
    ok( exists $memcached->{store}{'api_rl:anonymous:127.0.0.1'}, 'counted under the client address' );

    $client_ip = '203.0.113.9';
    $t->get_ok('/api/v1/public/libraries')->status_is( 200, 'another address has its own budget' );

    my $anonymous_session = session_for(undef);
    session_get( '/api/v1/public/libraries', $anonymous_session )->status_is( 200, 'anonymous session counted apart' );
    ok(
        ( grep { /^api_rl:anonymous:[0-9a-f]{16}$/ } keys %{ $memcached->{store} } ),
        'an anonymous session is keyed by its hash, not the address'
    );

    $schema->storage->txn_rollback;
};

subtest 'token class, POST /oauth/token per address' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTOAuth2ClientCredentials', 0 );
    limiter( token_limit => 2 );

    my $form = { grant_type => 'client_credentials', client_id => 'nope', client_secret => 'nope' };
    $t->post_ok( '/api/v1/oauth/token', form => $form )->status_is(400) for 1 .. 2;
    $t->post_ok( '/api/v1/oauth/token', form => $form )
        ->status_is( 429, 'counted although under skips authentication' );
    ok( exists $memcached->{store}{'api_rl:token:127.0.0.1'}, 'counted under the client address' );

    $schema->storage->txn_rollback;
};

subtest 'exempt addresses are never counted' => sub {
    plan tests => 7;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTPublicAPI',               1 );
    t::lib::Mocks::mock_preference( 'RESTPublicAnonymousRequests', 1 );
    limiter( anonymous_limit => 1, exempt_ips => '127.0.0.1' );

    $t->get_ok('/api/v1/public/libraries')->status_is(200) for 1 .. 3;
    is( scalar keys %{ $memcached->{store} }, 0, 'nothing counted for an exempt address' );

    $schema->storage->txn_rollback;
};

subtest 'observe mode logs and serves' => sub {
    plan tests => 5;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
    limiter( mode => 'observe', basic_limit => 1 );

    my ( $patron, $userid, $password ) = superlibrarian();
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(200);
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is( 200, 'served past the limit' );

    my $borrowernumber = $patron->borrowernumber;
    $logger->warn_like(
        qr/event=limited mode=observe class=basic id=$borrowernumber .* n=2 limit=1/,
        'the would-be refusal is logged'
    )->clear;

    $schema->storage->txn_rollback;
};

subtest 'fail open without memcached' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
    limiter( basic_limit => 1 );

    my ( $patron, $userid, $password ) = superlibrarian();

    $memcached = undef;
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(200) for 1 .. 2;

    $memcached = t::lib::Mocks::Memcached->new( fail => 1 );
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(200) for 1 .. 2;

    $schema->storage->txn_rollback;
};

subtest 'window is the counter lifetime and the Retry-After' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
    limiter( window => 45, basic_limit => 1 );

    my ( $patron, $userid, $password ) = superlibrarian();
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(200);
    is( $memcached->{ttl}{ 'api_rl:basic:' . $patron->borrowernumber }, 45, 'counter expires with the window' );
    $t->get_ok("//$userid:$password@/api/v1/libraries")->status_is(429)->header_is( 'Retry-After' => 45 );

    $schema->storage->txn_rollback;
};

subtest 'configure() defaults' => sub {
    plan tests => 5;

    t::lib::Mocks::mock_config( 'api_rate_limit', { enabled => 1, exempt_ips => '10.0.0.0/8 bogus' } );
    $logger->clear;
    my $plugin = $t->app->api_rate_limit->configure;

    is( $plugin->mode,   'enforce', 'default mode is enforce' );
    is( $plugin->window, 60,        'default window' );
    is_deeply(
        $plugin->limits,
        { oauth => 600, session => 600, basic => 300, anonymous => 60, token => 30 },
        'default limits'
    );
    is( scalar @{ $plugin->exempt_nets }, 1, 'only the parseable exempt network is kept' );
    $logger->warn_like( qr/exempt_ips: could not parse bogus/, 'the bad one is logged' )->clear;
};
