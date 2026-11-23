package Koha::BotGuard::ProofOfWork;

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

use Digest::SHA qw( hmac_sha256_hex sha256 );

use Koha::BotGuard::TrustCookie;
use Koha::Token;

# Seconds a puzzle stays solvable: long enough for a slow phone, short enough to bound replays
use constant TTL        => 300;
use constant CLOCK_SKEW => 300;

=head1 NAME

Koha::BotGuard::ProofOfWork - Stateless proof of work for the OPAC bot guard challenge

=head1 SYNOPSIS

    my $puzzle = Koha::BotGuard::ProofOfWork->issue(18);
    my $nonce  = Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, 18 );

=head1 DESCRIPTION

A puzzle is C<< <issued>.<nonce>.<difficulty>.<hmac> >>, signed with the trust cookie secret.
The browser has to find a counter so that sha256('<puzzle>.<counter>') starts with
<difficulty> zero bits. The nonce of a solved puzzle becomes the nonce of the trust cookie, so
one solution buys exactly one identity: replaying it gets a cookie with the same budget, not a
fresh one.

=head1 METHODS

=head2 issue

    my $puzzle = Koha::BotGuard::ProofOfWork->issue($difficulty);

A new signed puzzle, or undef when there is no secret.

=cut

sub issue {
    my ( $class, $difficulty ) = @_;

    my $issued = time;
    my $nonce  = Koha::Token->new->generate( { length => 16, pattern => '[a-f0-9]{16}' } );
    my $mac    = $class->_sign( $issued, $nonce, $difficulty ) or return;

    return join '.', $issued, $nonce, $difficulty, $mac;
}

=head2 verify

    my $nonce = Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, $difficulty );

The puzzle's nonce when the counter solves a genuine, unexpired puzzle of at least the
required difficulty, otherwise undef.

=cut

sub verify {
    my ( $class, $puzzle, $counter, $difficulty ) = @_;

    return unless defined $puzzle && defined $counter;
    my ( $issued, $nonce, $puzzle_difficulty, $mac ) =
        $puzzle =~ /^(\d{1,12})\.([0-9a-f]{16})\.(\d{1,2})\.([0-9a-f]{64})\z/
        or return;
    return unless $counter =~ /^\d{1,12}\z/;

    my $now = time;
    return if $puzzle_difficulty < $difficulty;
    return if $issued > $now + CLOCK_SKEW;
    return if $now - $issued > TTL;

    my $expected = $class->_sign( $issued, $nonce, $puzzle_difficulty ) or return;
    return unless Koha::BotGuard::TrustCookie->same_signature( $mac, $expected );
    return unless $class->leading_zero_bits( sha256("$puzzle.$counter") ) >= $puzzle_difficulty;

    return $nonce;
}

=head2 leading_zero_bits

    my $bits = Koha::BotGuard::ProofOfWork->leading_zero_bits($binary_digest);

The number of zero bits at the start of a binary string.

=cut

sub leading_zero_bits {
    my ( $class, $binary ) = @_;

    my $bits = 0;
    foreach my $byte ( unpack 'C*', $binary ) {
        if ( $byte == 0 ) {
            $bits += 8;
            next;
        }
        while ( !( $byte & 0x80 ) ) {
            $byte <<= 1;
            $bits++;
        }
        last;
    }
    return $bits;
}

=head2 solve

    my $counter = Koha::BotGuard::ProofOfWork->solve( $puzzle, $difficulty );

Brute forces a solution, for tests and command line checks. The challenge page has its own
solver.

=cut

sub solve {
    my ( $class, $puzzle, $difficulty ) = @_;

    my $counter = 0;
    $counter++ while $class->leading_zero_bits( sha256("$puzzle.$counter") ) < $difficulty;
    return $counter;
}

=head2 _sign

The HMAC for an issue time, nonce and difficulty, or undef without a secret.

=cut

sub _sign {
    my ( $class, $issued, $nonce, $difficulty ) = @_;

    my $secret = Koha::BotGuard::TrustCookie->secret or return;
    return hmac_sha256_hex( join( '.', 'KOHA_POW', $issued, $nonce, $difficulty ), $secret );
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
