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
use Test::More tests => 15;
use Test::MockModule;
use t::lib::Mocks;
use t::lib::Mocks::Logger;
use t::lib::Mocks::Memcached;

use Koha::BotGuard::ProofOfWork;
use Koha::BotGuard::TrustCookie;

use_ok("Koha::Middleware::BotGuard");

my $hits  = 0;
my $inner = sub { $hits++; return [ 200, [ 'Content-Type' => 'text/plain' ], ['ok'] ] };

my $logger = t::lib::Mocks::Logger->new;

my $memcached;
my $mock = Test::MockModule->new('Koha::RateLimit::Counter');
$mock->mock( memcached => sub { return $memcached } );

sub env {
    my (%override) = @_;
    return {
        REQUEST_METHOD    => 'GET',
        PATH_INFO         => '/opac-search.pl',
        QUERY_STRING      => q{},
        REMOTE_ADDR       => '203.0.113.5',
        HTTP_COOKIE       => q{},
        'psgi.url_scheme' => 'http',
        %override,
    };
}

sub guard {
    my (%config) = @_;
    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret', %config } );
    my $mw = Koha::Middleware::BotGuard->new( app => $inner );
    $mw->prepare_app;
    return $mw;
}

sub cookie_env {
    my ( $kind, %override ) = @_;
    return env( HTTP_COOKIE => 'CGISESSID=abc; KOHA_TRUST=' . Koha::BotGuard::TrustCookie->issue($kind), %override );
}

# An issue request carrying a solved puzzle of the given difficulty
sub solved_env {
    my ( $difficulty, %override ) = @_;
    my $puzzle  = Koha::BotGuard::ProofOfWork->issue($difficulty);
    my $counter = Koha::BotGuard::ProofOfWork->solve( $puzzle, $difficulty );
    return env( PATH_INFO => '/svc/opac_trust', QUERY_STRING => "pow=$puzzle&counter=$counter", %override );
}

sub header {
    my ( $response, $name ) = @_;
    my @headers = @{ $response->[1] };
    while ( my ( $key, $value ) = splice @headers, 0, 2 ) {
        return $value if lc $key eq lc $name;
    }
    return;
}

subtest 'disabled passthrough' => sub {
    plan tests => 4;

    t::lib::Mocks::mock_config( 'opac_bot_guard', undef );
    my $mw = Koha::Middleware::BotGuard->new( app => $inner );
    $mw->prepare_app;

    $hits = 0;
    is( $mw->call( env() )->[0],                                 200, 'heavy request passes when there is no config' );
    is( $hits,                                                   1,   'the app ran' );
    is( $mw->call( env( PATH_INFO => '/svc/opac_trust' ) )->[0], 204, 'issue endpoint answers 204 while disabled' );

    t::lib::Mocks::mock_config( 'api_secret_passphrase', undef );
    t::lib::Mocks::mock_config( 'opac_bot_guard',        { enabled => 1 } );
    $mw = Koha::Middleware::BotGuard->new( app => $inner );
    $mw->prepare_app;
    $logger->warn_like( qr/neither <secret> nor api_secret_passphrase/, 'no secret disables with a warning' )->clear;
};

subtest 'prepare_app() config and defaults' => sub {
    plan tests => 13;

    my $mw = guard();
    is( $mw->mode,                     'enforce', 'default mode is enforce' );
    is( $mw->rate_limit,               60,        'default rate_limit' );
    is( $mw->authenticated_rate_limit, 600,       'default authenticated_rate_limit' );
    is( $mw->rate_window,              60,        'default rate_window' );
    is( $mw->max_concurrent,           4,         'default max_concurrent' );
    is( $mw->issue_limit,              30,        'default issue_limit' );
    is( $mw->pow_difficulty,           18,        'default pow_difficulty' );
    ok( $mw->heavy->{'opac-search.pl'} && $mw->heavy->{'svc/shelfbrowser.pl'}, 'default heavy list loaded' );

    $mw = guard( rate_limit => q{}, heavy_scripts => q{} );
    ok(
        $mw->rate_limit == 60 && $mw->heavy->{'opac-search.pl'},
        'an empty element means the default, not 0'
    );

    $mw =
        guard( mode => 'observe', heavy_scripts => "opac-search.pl\n opac-main.pl", exempt_ips => '10.0.0.0/8 bogus' );
    $logger->warn_like(
        qr/exempt_ips: could not parse bogus/,
        'an exempt address that cannot be parsed is warned about'
    )->clear;
    is( $mw->mode, 'observe', 'observe mode honoured' );
    is_deeply(
        [ sort keys %{ $mw->heavy } ], [ 'opac-main.pl', 'opac-search.pl' ],
        'heavy_scripts override replaces the list'
    );
    is( scalar @{ $mw->exempt_nets }, 1, 'only the parseable exempt network is kept' );
};

subtest 'script_for_path() tests' => sub {
    plan tests => 11;

    my $mw = guard();
    is( $mw->script_for_path('/opac-search.pl'),              'opac-search.pl',      'plain script' );
    is( $mw->script_for_path('/opac-search.pl/extra'),        'opac-search.pl',      'path info suffix' );
    is( $mw->script_for_path('//opac-search.pl'),             'opac-search.pl',      'doubled slash' );
    is( $mw->script_for_path('/./opac-detail.pl'),            'opac-detail.pl',      'dot segment' );
    is( $mw->script_for_path('/cgi-bin/koha/opac-search.pl'), 'opac-search.pl',      'dev proxy path shape' );
    is( $mw->script_for_path('/opac/opac-search.pl'),         'opac-search.pl',      'packaged mount path shape' );
    is( $mw->script_for_path('/svc/shelfbrowser.pl'),         'svc/shelfbrowser.pl', 'svc script keeps its prefix' );
    is( $mw->script_for_path('/opac-main.pl'),                'opac-main.pl',        'light script still resolves' );
    is( $mw->script_for_path('/'),                            undef,                 'root resolves to nothing' );
    is( $mw->script_for_path(q{}),                            undef,                 'empty path' );
    is( $mw->script_for_path(undef),                          undef,                 'undef path' );
};

subtest 'requests that are never challenged' => sub {
    plan tests => 10;

    my $mw = guard( exempt_ips => '192.0.2.0/24' );
    $hits = 0;
    is( $mw->call( env( PATH_INFO    => '/opac-main.pl' ) )->[0],    200, 'light script passes' );
    is( $mw->call( env( PATH_INFO    => '/opac-user.pl' ) )->[0],    200, 'login page passes' );
    is( $mw->call( env( PATH_INFO    => '/ilsdi.pl' ) )->[0],        200, 'ILS-DI passes' );
    is( $mw->call( env( PATH_INFO    => '/opac-image.pl' ) )->[0],   200, 'cover images pass' );
    is( $mw->call( env( PATH_INFO    => '/svc/club/enroll' ) )->[0], 200, 'other svc scripts pass' );
    is( $mw->call( env( QUERY_STRING => 'q=a&format=rss' ) )->[0],   200, 'RSS feed passes without a cookie' );
    is( $mw->call( env( QUERY_STRING => 'format=opensearchdescription' ) )->[0], 200, 'OpenSearch description passes' );
    is(
        $mw->call( env( PATH_INFO => '/opac-shelves.pl', QUERY_STRING => 'op=view&shelfnumber=1&rss=1' ) )->[0],
        200, 'public list RSS feed passes without a cookie'
    );
    is( $mw->call( env( REMOTE_ADDR => '192.0.2.77' ) )->[0], 200, 'exempt address passes' );
    is(
        $mw->call( env( 'psgix.errordocument.SCRIPT_NAME' => '/errors/404.pl' ) )->[0], 200,
        'ErrorDocument subrequest passes'
    );
};

subtest 'challenge' => sub {
    plan tests => 16;

    my $mw = guard();
    $hits = 0;

    my $response = $mw->call( env() );
    is( $response->[0], 200, 'cookie-less heavy GET gets the challenge page' );
    is( $hits,          0,   'the app did not run' );
    like( header( $response, 'Content-Type' ),  qr{text/html}, 'challenge is HTML' );
    like( header( $response, 'Cache-Control' ), qr/no-store/,  'challenge is never cached' );
    is( header( $response, 'X-Koha-BotGuard' ), 'challenge', 'challenge is marked for the logs' );
    like( $response->[2][0], qr{/cgi-bin/koha/svc/opac_trust}, 'page calls the issue endpoint' );
    like(
        $response->[2][0], qr/var puzzle = '\d+\.[0-9a-f]{16}\.18\.[0-9a-f]{64}', difficulty = 18;/,
        'page carries a signed puzzle'
    );

    my %challenged = (
        'format=rss on a record'      => [ '/opac-detail.pl',       'biblionumber=1&format=rss' ],
        'format=rss on a MARC export' => [ '/opac-export.pl',       'op=export&bib=1&format=rss' ],
        'the cart'                    => [ '/opac-basket.pl',       'bib_list=1/2/3' ],
        'a cart download'             => [ '/opac-downloadcart.pl', 'bib_list=1/2/3&format=iso2709' ],
    );
    foreach my $what ( sort keys %challenged ) {
        my ( $path, $query ) = @{ $challenged{$what} };
        is(
            header( $mw->call( env( PATH_INFO => $path, QUERY_STRING => $query ) ), 'X-Koha-BotGuard' ),
            'challenge', "$what is challenged"
        );
    }

    is( $mw->call( env( REQUEST_METHOD => 'HEAD' ) )->[0], 200, 'HEAD is challenged too' );
    is( $mw->call( env( REQUEST_METHOD => 'POST' ) )->[0], 200, 'POST is challenged too' );
    is(
        $mw->call( env( QUERY_STRING => 'format=html&format=rss' ) )->[2][0] =~ /opac_trust/ ? 1 : 0, 1,
        'only the first format parameter counts'
    );

    my $tampered = cookie_env('anonymous');
    substr( $tampered->{HTTP_COOKIE}, -1, 1 ) = substr( $tampered->{HTTP_COOKIE}, -1, 1 ) eq '0' ? '1' : '0';
    is( header( $mw->call($tampered), 'X-Koha-BotGuard' ), 'challenge', 'a tampered cookie is challenged' );
    is( $hits,                                             0,           'no challenged request reached the app' );
};

subtest 'issue endpoint' => sub {
    plan tests => 19;

    my $mw = guard( issue_limit => 3, pow_difficulty => 4 );
    $memcached = t::lib::Mocks::Memcached->new;
    $hits      = 0;
    $logger->clear;

    my $response = $mw->call( env( PATH_INFO => '/svc/opac_trust' ) );
    is( $response->[0],                         422,                      'a GET without a solved puzzle is refused' );
    is( header( $response, 'X-Koha-BotGuard' ), 'proof_of_work_required', 'and says why' );
    is( header( $response, 'Set-Cookie' ),      undef,                    'and sets no cookie' );
    is( $logger->count('warn'),                 0,                        'and is not logged outside observe mode' );

    my $unsolved = solved_env(4);
    $unsolved->{QUERY_STRING} =~ s/counter=\d+/counter=x/;
    is( $mw->call($unsolved)->[0], 422, 'a wrong solution is refused' );

    my $solved = solved_env(4);
    my ($puzzle_nonce) = $solved->{QUERY_STRING} =~ /^pow=\d+\.([0-9a-f]{16})\./;
    $response = $mw->call($solved);
    is( $response->[0], 204, 'a solved puzzle issues a cookie' );
    like(
        header( $response, 'Set-Cookie' ),
        qr/^KOHA_TRUST=anonymous\.\d+\.[0-9a-f]{16}\.[0-9a-f]{64}; Path=\/; Max-Age=\d+; HttpOnly; SameSite=Lax$/,
        'anonymous cookie with the expected attributes, no Secure on http'
    );
    like( header( $response, 'Set-Cookie' ), qr/^KOHA_TRUST=anonymous\.\d+\.$puzzle_nonce\./, 'with the puzzle nonce' );

    like(
        header( $mw->call($solved), 'Set-Cookie' ), qr/^KOHA_TRUST=anonymous\.\d+\.$puzzle_nonce\./,
        'a replayed solution gets the same nonce, so the same budget'
    );

    $response = $mw->call( solved_env( 4, 'psgi.url_scheme' => 'https' ) );
    like( header( $response, 'Set-Cookie' ), qr/; Secure$/, 'Secure flag on https' );

    $response = $mw->call( solved_env(4) );
    $logger->warn_like( qr/event=issue_limited .* n=4 limit=3/, 'the refusal is logged' )->clear;
    is( $response->[0],                     429, 'fourth cookie for the same address in a minute is refused' );
    is( header( $response, 'Retry-After' ), 60,  'with a Retry-After' );

    $response = $mw->call( cookie_env( 'anonymous', PATH_INFO => '/svc/opac_trust' ) );
    is( $response->[0],                    204,   'a client with a valid cookie gets 204' );
    is( header( $response, 'Set-Cookie' ), undef, 'and keeps the cookie it has' );

    is( $mw->call( env( PATH_INFO => '/svc/opac_trust', REQUEST_METHOD => 'POST' ) )->[0], 405, 'POST is not allowed' );
    is( $hits,                                                                             0,   'the app never ran' );

    $mw        = guard( pow_difficulty => 0 );
    $memcached = t::lib::Mocks::Memcached->new;
    $response  = $mw->call( env( PATH_INFO => '/svc/opac_trust' ) );
    is( $response->[0], 204, 'with pow_difficulty 0 a plain GET issues a cookie' );
    like( $mw->challenge_response->[2][0], qr/difficulty = 0;/, 'and the challenge page asks for no work' );
};

subtest 'valid cookie is admitted' => sub {
    plan tests => 3;

    my $mw = guard();
    $memcached = t::lib::Mocks::Memcached->new;
    $hits      = 0;

    my $response = $mw->call( cookie_env('anonymous') );
    is( $response->[0],                           200, 'request with a valid anonymous cookie is admitted' );
    is( $hits,                                    1,   'the app ran' );
    is( $memcached->{store}{'botguard:inflight'}, 0,   'in-flight count is back to zero' );
};

subtest 'per cookie rate limit' => sub {
    plan tests => 9;

    my $mw = guard( rate_limit => 3, rate_window => 45 );
    $memcached = t::lib::Mocks::Memcached->new;
    $hits      = 0;

    my $env = cookie_env('anonymous');
    is( $mw->call($env)->[0], 200, 'first request admitted' ) for 1 .. 1;
    is( $mw->call($env)->[0], 200, 'second request admitted' );
    is( $mw->call($env)->[0], 200, 'third request admitted' );

    my $response;
    $response = $mw->call($env);
    $logger->warn_like(
        qr/botguard event=limited mode=enforce ip=203\.0\.113\.5 .* n=4 limit=3/,
        'the refusal is logged'
    )->clear;
    is( $response->[0],                     429, 'fourth request is refused' );
    is( header( $response, 'Retry-After' ), 45,  'Retry-After is the window' );

    is( $mw->call($env)->[0],   429, 'fifth request is refused too' );
    is( $logger->count('warn'), 0,   'but only the first refusal in the window is logged' );

    is( $mw->call( cookie_env('anonymous') )->[0], 200, 'a different cookie has its own budget' );
};

subtest 'feeds are limited per address' => sub {
    plan tests => 6;

    my $mw = guard( rate_limit => 2 );
    $memcached = t::lib::Mocks::Memcached->new;

    my $feed = env( QUERY_STRING => 'q=a&format=rss' );
    is( $mw->call($feed)->[0], 200, 'first feed request served' );
    is( $mw->call($feed)->[0], 200, 'second feed request served' );

    my $response = $mw->call($feed);
    $logger->warn_like( qr/botguard event=limited .* cid=- n=3 limit=2/, 'the refusal is logged' )->clear;
    is( $response->[0], 429, 'third feed request from the same address is refused' );

    is(
        $mw->call( env( PATH_INFO => '/opac-shelves.pl', QUERY_STRING => 'op=view&shelfnumber=1&rss=1' ) )->[0],
        429, 'list feeds share the same budget'
    );
    is( $mw->call( env( %$feed, REMOTE_ADDR => '198.51.100.7' ) )->[0], 200, 'another address has its own budget' );
};

subtest 'concurrency cap' => sub {
    plan tests => 8;

    my $mw = guard( max_concurrent => 1 );
    $memcached                               = t::lib::Mocks::Memcached->new;
    $memcached->{store}{'botguard:inflight'} = 1;                               # one anonymous request already running
    $hits                                    = 0;

    my $response;
    $response = $mw->call( cookie_env('anonymous') );
    $logger->warn_like( qr/botguard event=capped .* n=2 limit=1/, 'the refusal is logged' )->clear;
    is( $response->[0],                           503, 'request over the cap gets 503' );
    is( header( $response, 'Retry-After' ),       2,   'with a short Retry-After' );
    is( $memcached->{store}{'botguard:inflight'}, 1,   'the refused request is not left counted' );
    is( $hits,                                    0,   'the app did not run' );

    $response = $mw->call( env( QUERY_STRING => 'format=rss' ) );
    is( $response->[0],         503, 'feeds count toward the cap and are refused over it' );
    is( $logger->count('warn'), 0,   'a second refusal within ten seconds is not logged' );

    $memcached->{store}{'botguard:inflight'} = 0;
    my $dying = Koha::Middleware::BotGuard->new( app => sub { die "boom\n" } );
    $dying->prepare_app;
    eval { $dying->call( cookie_env('anonymous') ) };
    is( $memcached->{store}{'botguard:inflight'}, 0, 'a dying app still releases its slot' );
};

subtest 'fail open without memcached' => sub {
    plan tests => 4;

    my $mw = guard( rate_limit => 1, max_concurrent => 1 );
    $hits = 0;

    $memcached = undef;
    my $env = cookie_env('anonymous');
    is( $mw->call($env)->[0], 200, 'admitted with no memcached handle' );
    is( $mw->call($env)->[0], 200, 'and again, past the limit' );

    $memcached = t::lib::Mocks::Memcached->new( fail => 1 );
    is( $mw->call($env)->[0],                                 200, 'admitted when memcached errors' );
    is( $mw->call( env() )->[0] == 200 && $hits == 3 ? 1 : 0, 1,   'cookie-less requests are still challenged' );
};

subtest 'logged in cookie skips the cap and gets a higher limit' => sub {
    plan tests => 5;

    my $mw = guard( rate_limit => 1, max_concurrent => 1, authenticated_rate_limit => 2 );
    $memcached                               = t::lib::Mocks::Memcached->new;
    $memcached->{store}{'botguard:inflight'} = 5;
    $hits                                    = 0;

    my $env = cookie_env('authenticated');
    is( $mw->call($env)->[0],                     200, 'admitted' );
    is( $mw->call($env)->[0],                     200, 'admitted again past the anonymous rate_limit and the cap' );
    is( $memcached->{store}{'botguard:inflight'}, 5,   'the in-flight count was never touched' );

    my $response = $mw->call($env);
    $logger->warn_like( qr/botguard event=limited .* n=3 limit=2/, 'the refusal is logged' )->clear;
    is( $response->[0], 429, 'refused past authenticated_rate_limit, so a shared cookie is not unlimited' );
};

subtest 'observe mode' => sub {
    plan tests => 8;

    my $mw = guard( mode => 'observe', rate_limit => 1 );
    $memcached = t::lib::Mocks::Memcached->new;
    $hits      = 0;

    my $response;
    $response = $mw->call( env() );
    $logger->warn_like( qr/botguard event=challenge mode=observe/, 'a would-be challenge is logged' )->clear;
    is( $response->[0], 200, 'and the request goes through' );
    is( $hits,          1,   'to the app' );

    my $env = cookie_env('anonymous');
    $mw->call($env);
    $response = $mw->call($env);
    $logger->warn_like( qr/event=limited mode=observe/, 'a would-be 429 is logged' )->clear;
    is( $response->[2][0], 'ok', 'and the app answered anyway' );

    $response = $mw->call( env( PATH_INFO => '/svc/opac_trust' ) );
    $logger->warn_like( qr/botguard event=pow_required mode=observe/, 'a would-be missing proof of work is logged' )
        ->clear;
    is( $response->[0], 204, 'and a cookie is issued anyway' );
    like( header( $response, 'Set-Cookie' ), qr/^KOHA_TRUST=anonymous\./, 'an anonymous one' );
};
