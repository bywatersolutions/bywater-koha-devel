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
use Test::More tests => 7;

use Digest::SHA qw( sha256 );

use t::lib::Mocks;

use_ok("Koha::BotGuard::ProofOfWork");

t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );

subtest 'leading_zero_bits() tests' => sub {
    plan tests => 5;

    is( Koha::BotGuard::ProofOfWork->leading_zero_bits("\x80"),         0,  'high bit set' );
    is( Koha::BotGuard::ProofOfWork->leading_zero_bits("\x01"),         7,  'low bit set' );
    is( Koha::BotGuard::ProofOfWork->leading_zero_bits("\x00\x00\x40"), 17, 'zero bytes count eight each' );
    is( Koha::BotGuard::ProofOfWork->leading_zero_bits("\x00\x00"),     16, 'all zeros' );
    is( Koha::BotGuard::ProofOfWork->leading_zero_bits("\x0f\x00"),     4,  'only leading bits count' );
};

subtest 'issue() and verify() round trip' => sub {
    plan tests => 5;

    my $puzzle = Koha::BotGuard::ProofOfWork->issue(8);
    like( $puzzle, qr/^\d+\.[0-9a-f]{16}\.8\.[0-9a-f]{64}$/, 'puzzle has the expected shape' );

    my $counter = Koha::BotGuard::ProofOfWork->solve( $puzzle, 8 );
    ok( Koha::BotGuard::ProofOfWork->leading_zero_bits( sha256("$puzzle.$counter") ) >= 8, 'solve() finds a solution' );

    my ($nonce) = $puzzle =~ /^\d+\.([0-9a-f]{16})\./;
    is( Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 8 ), $nonce, 'a solution returns the puzzle nonce' );
    is(
        Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 8 ), $nonce,
        'a replayed solution returns the same nonce'
    );
    isnt( Koha::BotGuard::ProofOfWork->issue(8), $puzzle, 'every puzzle gets its own nonce' );
};

subtest 'verify() rejects bad solutions' => sub {
    plan tests => 9;

    my $puzzle  = Koha::BotGuard::ProofOfWork->issue(8);
    my $counter = Koha::BotGuard::ProofOfWork->solve( $puzzle, 8 );

    # The first counter that does not solve it
    my $wrong = 0;
    $wrong++ while Koha::BotGuard::ProofOfWork->leading_zero_bits( sha256("$puzzle.$wrong") ) >= 8;
    is( Koha::BotGuard::ProofOfWork->verify( $puzzle, $wrong, 8 ), undef, 'a counter that does not solve it' );

    is( Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 9 ), undef, 'a puzzle easier than required' );

    ( my $easier = $puzzle ) =~ s/\.8\./.1./;
    is( Koha::BotGuard::ProofOfWork->verify( $easier, 0, 1 ), undef, 'lowering the difficulty breaks the signature' );

    my $flipped = $puzzle;
    substr( $flipped, -1, 1 ) = substr( $flipped, -1, 1 ) eq '0' ? '1' : '0';
    is( Koha::BotGuard::ProofOfWork->verify( $flipped, $counter, 8 ), undef, 'a changed signature' );

    is( Koha::BotGuard::ProofOfWork->verify( $puzzle,   'x',   8 ), undef, 'a counter that is not a number' );
    is( Koha::BotGuard::ProofOfWork->verify( 'garbage', 1,     8 ), undef, 'garbage' );
    is( Koha::BotGuard::ProofOfWork->verify( undef,     undef, 8 ), undef, 'nothing' );

    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'rotated-secret' } );
    is( Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 8 ), undef, 'a puzzle signed with an old secret' );
    t::lib::Mocks::mock_config( 'opac_bot_guard', { enabled => 1, secret => 'test-secret' } );
    is( Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 8 ) ? 1 : 0, 1, 'accepted again with the secret back' );
};

subtest 'verify() enforces the lifetime' => sub {
    plan tests => 3;

    my $build = sub {
        my ($issued) = @_;
        my $nonce    = 'abcdef0123456789';
        my $puzzle   = join '.', $issued, $nonce, 4, Koha::BotGuard::ProofOfWork->_sign( $issued, $nonce, 4 );
        return ( $puzzle, Koha::BotGuard::ProofOfWork->solve( $puzzle, 4 ) );
    };

    ok( Koha::BotGuard::ProofOfWork->verify( $build->( time - 200 ), 4 ), 'a puzzle inside its lifetime' );
    is( Koha::BotGuard::ProofOfWork->verify( $build->( time - 301 ), 4 ), undef, 'an expired puzzle' );
    is( Koha::BotGuard::ProofOfWork->verify( $build->( time + 301 ), 4 ), undef, 'a puzzle from the future' );
};

subtest 'no secret' => sub {
    plan tests => 1;

    t::lib::Mocks::mock_config( 'opac_bot_guard',        { enabled => 1 } );
    t::lib::Mocks::mock_config( 'api_secret_passphrase', undef );
    is( Koha::BotGuard::ProofOfWork->issue(8), undef, 'no puzzle can be issued without a secret' );
};
