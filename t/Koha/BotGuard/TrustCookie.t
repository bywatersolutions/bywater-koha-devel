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
use Test::More tests => 8;

use CGI;

use t::lib::Mocks;

use_ok("Koha::BotGuard::TrustCookie");

subtest 'enabled() and secret() tests' => sub {
    plan tests => 6;

    t::lib::Mocks::mock_config( 'opac_bot_guard',        undef );
    t::lib::Mocks::mock_config( 'api_secret_passphrase', 'fleet-passphrase' );
    is( Koha::BotGuard::TrustCookie->enabled, 0, 'disabled when there is no opac_bot_guard block' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1 } );
    is( Koha::BotGuard::TrustCookie->enabled, 1,                  'enabled with the block and a passphrase' );
    is( Koha::BotGuard::TrustCookie->secret,  'fleet-passphrase', 'secret falls back to api_secret_passphrase' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'own-secret' } );
    is( Koha::BotGuard::TrustCookie->secret, 'own-secret', 'a configured secret wins over the passphrase' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => {} } );
    is( Koha::BotGuard::TrustCookie->secret, 'fleet-passphrase', 'an empty <secret></secret> element is ignored' );

    t::lib::Mocks::mock_config( 'api_secret_passphrase', undef );
    is( Koha::BotGuard::TrustCookie->issue('anonymous'), undef, 'no cookie can be issued without any secret' );
};

subtest 'issue() and verify() round trip' => sub {
    plan tests => 8;

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );

    my $anonymous = Koha::BotGuard::TrustCookie->issue('anonymous');
    like( $anonymous, qr/^anonymous\.\d+\.[0-9a-f]{16}\.[0-9a-f]{64}$/, 'anonymous cookie has the expected shape' );

    my $trust = Koha::BotGuard::TrustCookie->verify($anonymous);
    is( $trust->{kind}, 'anonymous', 'anonymous kind round trips' );
    like( $trust->{nonce}, qr/^[0-9a-f]{16}$/, 'nonce round trips' );
    ok( time - $trust->{issued} < 5, 'issued time is now' );

    my $patron = Koha::BotGuard::TrustCookie->issue('authenticated');
    like( $patron, qr/^authenticated\./, 'patron cookie carries the authenticated kind' );
    is( Koha::BotGuard::TrustCookie->verify($patron)->{kind}, 'authenticated', 'authenticated kind round trips' );

    like( Koha::BotGuard::TrustCookie->issue('x'), qr/^anonymous\./, 'an unknown kind is issued as anonymous' );

    isnt(
        Koha::BotGuard::TrustCookie->issue('anonymous'), $anonymous,
        'every cookie gets its own nonce'
    );
};

subtest 'verify() rejects tampered values' => sub {
    plan tests => 7;

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );

    my $value = Koha::BotGuard::TrustCookie->issue('anonymous');

    my $flipped = $value;
    substr( $flipped, -1, 1 ) = substr( $flipped, -1, 1 ) eq '0' ? '1' : '0';
    is( Koha::BotGuard::TrustCookie->verify($flipped), undef, 'a changed signature is rejected' );

    ( my $upgraded = $value ) =~ s/^anonymous\./authenticated./;
    is( Koha::BotGuard::TrustCookie->verify($upgraded), undef, 'changing the kind breaks the signature' );

    is( Koha::BotGuard::TrustCookie->verify('garbage'), undef, 'garbage is rejected' );
    is( Koha::BotGuard::TrustCookie->verify(q{}),       undef, 'an empty value is rejected' );
    is( Koha::BotGuard::TrustCookie->verify(undef),     undef, 'undef is rejected' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'rotated-secret' } );
    is( Koha::BotGuard::TrustCookie->verify($value), undef, 'a cookie signed with the old secret is rejected' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );
    ok( Koha::BotGuard::TrustCookie->verify($value), 'and accepted again once the secret is back' );
};

subtest 'verify() enforces the lifetime' => sub {
    plan tests => 4;

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret', cookie_ttl => 10 } );

    my $nonce = 'abcdef0123456789';
    my $build = sub {
        my ($issued) = @_;
        return join '.', 'anonymous', $issued, $nonce,
            Koha::BotGuard::TrustCookie->_sign( 'anonymous', $issued, $nonce );
    };

    ok( Koha::BotGuard::TrustCookie->verify( $build->( time - 5 ) ), 'a cookie inside the ttl is valid' );
    is( Koha::BotGuard::TrustCookie->verify( $build->( time - 11 ) ), undef, 'a cookie past the ttl is expired' );
    is(
        Koha::BotGuard::TrustCookie->verify( $build->( time + 301 ) ), undef,
        'a cookie issued in the future is rejected'
    );
    ok( Koha::BotGuard::TrustCookie->verify( $build->( time + 299 ) ), 'a little clock skew is tolerated' );
};

subtest 'set_cookie_header() tests' => sub {
    plan tests => 5;

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret', cookie_ttl => 3600 } );

    my $header = Koha::BotGuard::TrustCookie->set_cookie_header('anonymous');
    like( $header, qr/^KOHA_TRUST=anonymous\.\d+\.[0-9a-f]{16}\.[0-9a-f]{64}; /, 'header starts with the cookie' );
    like( $header, qr/; Path=\/; Max-Age=3600; HttpOnly; SameSite=Lax$/, 'attributes follow, no Secure on http' );
    unlike( $header, qr/Secure/, 'no Secure flag without https' );

    $header = Koha::BotGuard::TrustCookie->set_cookie_header( 'authenticated', { secure => 1 } );
    like( $header, qr/^KOHA_TRUST=authenticated\./, 'authenticated kind is honoured' );
    like( $header, qr/; Secure$/,                   'Secure flag added for https' );
};

subtest 'cgi_cookie() tests' => sub {
    plan tests => 6;

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );

    my $query = CGI->new;

    local $ENV{HTTPS} = undef;
    my $cookie = Koha::BotGuard::TrustCookie->cgi_cookie( $query, 'authenticated' );
    isa_ok( $cookie, 'CGI::Cookie' );
    is( $cookie->name, 'KOHA_TRUST', 'cookie is named KOHA_TRUST' );
    like( $cookie->value, qr/^authenticated\./, 'value carries the requested kind' );
    ok( $cookie->httponly, 'cookie is HttpOnly' );
    is( $cookie->samesite, 'Lax', 'cookie is SameSite=Lax' );

    $ENV{HTTPS} = 'ON';
    $cookie = Koha::BotGuard::TrustCookie->cgi_cookie( $query, 'anonymous' );
    ok( $cookie->secure, 'cookie is Secure under https' );
};
