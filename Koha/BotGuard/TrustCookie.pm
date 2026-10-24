package Koha::BotGuard::TrustCookie;

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

use Digest::SHA qw( hmac_sha256_hex );

use C4::Context;
use Koha::AuthUtils;
use Koha::Token;

use constant COOKIE_NAME => 'KOHA_TRUST';
use constant DEFAULT_TTL => 2592000;        # 30 days
use constant CLOCK_SKEW  => 300;

=head1 NAME

Koha::BotGuard::TrustCookie - Signed OPAC trust cookie used by Koha::Middleware::BotGuard

=head1 SYNOPSIS

    my $value  = Koha::BotGuard::TrustCookie->issue('anonymous');
    my $trust  = Koha::BotGuard::TrustCookie->verify( $query->cookie('KOHA_TRUST') );
    my $cookie = Koha::BotGuard::TrustCookie->cgi_cookie( $query, 'authenticated' );

=head1 DESCRIPTION

The cookie value is C<< <kind>.<issued>.<nonce>.<hmac> >>. The kind is 'anonymous'
for a cookie earned through the bot guard challenge page and 'authenticated' for
one issued to a logged-in patron. The HMAC covers all three fields, so none of them can be changed
without the secret from koha-conf.xml.

=head1 METHODS

=head2 config

The opac_bot_guard block from koha-conf.xml, or an empty hashref. Empty elements are left
out so every caller falls back to its default for them.

=cut

sub config {
    my $config = C4::Context->config('opac_bot_guard');
    return {} unless ref $config eq 'HASH';
    return { map { $_ => $config->{$_} } grep { length $config->{$_} } keys %$config };
}

=head2 enabled

True when the feature is turned on and a secret is available.

=cut

sub enabled {
    my ($class) = @_;
    return $class->config->{enabled} && $class->secret ? 1 : 0;
}

=head2 secret

The signing secret, falling back to api_secret_passphrase.

=cut

sub secret {
    my ($class) = @_;
    return $class->config->{secret} || C4::Context->config('api_secret_passphrase');
}

=head2 ttl

Seconds a cookie stays valid.

=cut

sub ttl {
    my ($class) = @_;
    return $class->config->{cookie_ttl} || DEFAULT_TTL;
}

=head2 issue

    my $value = Koha::BotGuard::TrustCookie->issue( $kind, $nonce );

Returns a new signed cookie value, or undef when there is no secret. The nonce is the identity
the bot guard counts requests under; a new one is generated unless it is passed in.

=cut

sub issue {
    my ( $class, $kind, $nonce ) = @_;

    $kind = 'anonymous' unless $kind && $kind eq 'authenticated';
    my $issued = time;
    $nonce //= Koha::Token->new->generate( { length => 16, pattern => '[a-f0-9]{16}' } );
    my $signature = $class->_sign( $kind, $issued, $nonce ) or return;

    return join '.', $kind, $issued, $nonce, $signature;
}

=head2 verify

    my $trust = Koha::BotGuard::TrustCookie->verify($value);

Returns a hashref with kind, issued and nonce for a valid, unexpired cookie, or undef.

=cut

sub verify {
    my ( $class, $value ) = @_;

    return unless defined $value;
    my ( $kind, $issued, $nonce, $signature ) =
        $value =~ /^(anonymous|authenticated)\.(\d{1,12})\.([0-9a-f]{16})\.([0-9a-f]{64})\z/
        or return;

    my $now = time;
    return if $issued > $now + CLOCK_SKEW;
    return if $now - $issued > $class->ttl;

    my $expected = $class->_sign( $kind, $issued, $nonce ) or return;
    return unless $class->same_signature( $signature, $expected );

    return { kind => $kind, issued => $issued, nonce => $nonce };
}

=head2 same_signature

    my $ok = Koha::BotGuard::TrustCookie->same_signature( $signature, $expected );

True when two hex signatures of the same length are identical.

=cut

sub same_signature {
    my ( $class, $signature, $expected ) = @_;

    return 0 unless length($signature) == length($expected);

    # Compare every byte so the time taken doesn't reveal how much of a forged signature was right
    my $difference = 0;
    $difference |= ord( substr( $signature, $_, 1 ) ) ^ ord( substr( $expected, $_, 1 ) )
        for 0 .. length($expected) - 1;
    return $difference ? 0 : 1;
}

=head2 set_cookie_header

    my $header = Koha::BotGuard::TrustCookie->set_cookie_header( $kind, { secure => 1, nonce => $nonce } );

The value for a raw Set-Cookie header, for use from PSGI middleware.

=cut

sub set_cookie_header {
    my ( $class, $kind, $params ) = @_;

    my $value  = $class->issue( $kind, $params->{nonce} ) or return;
    my $header = sprintf '%s=%s; Path=/; Max-Age=%d; HttpOnly; SameSite=Lax', COOKIE_NAME, $value, $class->ttl;
    $header .= '; Secure' if $params->{secure};
    return $header;
}

=head2 cgi_cookie

    my $cookie = Koha::BotGuard::TrustCookie->cgi_cookie( $query, $kind );

A CGI::Cookie with the same attributes, for use from C4::Auth.

=cut

sub cgi_cookie {
    my ( $class, $query, $kind ) = @_;

    my $value = $class->issue($kind) or return;
    return $query->cookie(
        -name     => COOKIE_NAME,
        -value    => $value,
        -path     => '/',
        -expires  => '+' . $class->ttl . 's',
        -HttpOnly => 1,
        -secure   => ( C4::Context->https_enabled() ? 1 : 0 ),
        -sameSite => 'Lax',
    );
}

=head2 _sign

The HMAC for a kind, issue time and nonce, or undef without a secret.

=cut

sub _sign {
    my ( $class, $kind, $issued, $nonce ) = @_;

    my $secret = $class->secret or return;
    return hmac_sha256_hex( join( '.', COOKIE_NAME, $kind, $issued, $nonce ), $secret );
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
