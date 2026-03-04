package Koha::ContentSecurityPolicy;

# Copyright 2025 Hypernova Oy, Koha Development Team
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

use C4::Context;
use Koha::Token;

use Koha::Exceptions::Config;

#NOTE: To cache the nonce, we just use a package level variable,
#which will be reset after every HTTP request.
my $cached_nonce;

=head1 NAME

Koha::ContentSecurityPolicy - Object for handling Content-Security-Policy header

=head1 SYNOPSIS

    use Koha::ContentSecurityPolicy;

    my $csp = Koha::ContentSecurityPolicy->new;

    if ($csp->is_enabled) {
        $options->{$csp->header_name} = $csp->header_value;
    }

    print $cgi->header($options), $data;

=head1 DESCRIPTION

TODO

=head1 METHODS

=head2 new

    my $csp = Koha::ContentSecurityPolicy->new;

=cut

sub new {
    my ( $class, $params ) = @_;
    my $self = bless $params // {}, $class;

    $self->set_nonce( $params->{nonce} ) if $params->{nonce};
    $self->{config} = Koha::Config->get_instance;
    return $self;
}

=head2 header_name

    $csp->header_name($args);

    Given C<$args>, returns the name of the CSP header.

    C<$args> can contain the following keys (and values)

    - interface:
        - defaults to L<C4::Context>->interface.
        - can be one of: C<opac>, C<intranet>

    Returns 'Content-Security-Policy' if CSP is in "enabled" csp_mode
    Returns 'Content-Security-Policy-Report-Only' if CSP in "report-only" csp_mode

    Throws Koha::Exceptions::Config::MissingEntry is CSP csp_mode is disabled in KOHA_CONF

=cut

sub header_name {
    my ( $self, $args ) = @_;

    my $interface = $args->{interface} || C4::Context->interface;

    my $conf_csp = $self->{config}->get('content_security_policy');

    if ( $conf_csp && $conf_csp->{$interface} && $conf_csp->{$interface}->{csp_mode} ) {
        return 'Content-Security-Policy-Report-Only' if $conf_csp->{$interface}->{csp_mode} eq 'report-only';
        return 'Content-Security-Policy'             if $conf_csp->{$interface}->{csp_mode} eq 'enabled';
    }

    Koha::Exceptions::Config::MissingEntry->throw(
        error => 'Content Security Policy is disabled. Header name should only be retrieved when CSP is enabled.' );
}

=head2 header_value

    $csp->header_value($args);

    Given C<$args>, returns the value of the CSP header.

    C<$args> can contain the following keys (and values)

    - interface:
        - defaults to L<C4::Context>->interface.
        - can be one of: C<opac>, C<intranet>

    Returns content_security_policy.[opac|staff].csp_header_value

=cut

sub header_value {
    my ( $self, $args ) = @_;

    my $interface = $args->{interface} || C4::Context->interface;

    my @default_policy_lines = (
        q#default-src 'self'#,
        q# script-src 'self' 'nonce-_CSP_NONCE_'#,
        q# style-src 'self' 'nonce-_CSP_NONCE_'#,
        q# style-src-attr 'unsafe-inline'#,
        q# img-src 'self' data:#,
        q# font-src 'self'#,
        q# object-src 'none'#,
    );
    my $default_policy = join( ';', @default_policy_lines );

    my $conf_csp = $self->{config}->get('content_security_policy');

    my $user_policy = $conf_csp->{$interface}->{csp_header_value};

    my $csp_policy = ($user_policy) ? $user_policy : $default_policy;

    my $csp_header_value = $csp_policy;
    my $csp_nonce        = $self->get_nonce;

    if ($csp_nonce) {
        $csp_header_value =~ s/_CSP_NONCE_/$csp_nonce/g;
    }

    return $csp_header_value;
}

=head2 is_enabled

    $csp->is_enabled($args);

    Given C<$args>, checks if CSP is enabled

    C<$args> can contain the following keys (and values)

    - interface:
        - defaults to L<C4::Context>->interface.
        - can be one of: C<opac>, C<intranet>

    Returns 0 if CSP is disabled for given C<$args>
    Returns 1 if CSP is enabled for given C<$args>

=cut

sub is_enabled {
    my ( $self, $args ) = @_;
    my $interface = $args->{interface} || C4::Context->interface;

    my $conf_csp = $self->{config}->get('content_security_policy');

    return 0 if $interface ne 'opac' && $interface ne 'intranet';

    return 0 unless exists $conf_csp->{$interface}->{csp_mode};
    return 1
        if $conf_csp->{$interface}->{csp_mode} eq 'report-only'
        or $conf_csp->{$interface}->{csp_mode} eq 'enabled';
    return 0;
}

=head2 get_nonce

    $csp->get_nonce();

    Returns the previously set nonce.

    A CSP nonce is a random token that is used both in the inline scripts
    and the Content-Security-Policy[-Report-Only] response header.

=cut

sub get_nonce {
    my ($self) = @_;

    #Koha::Middleware::ContentSecurityPolicy sets an environmental variable
    #We cannot use the L1 cache since it is cleared after the middleware is applied
    my $env_value = $cached_nonce;

    return $env_value;
}

=head2 set_nonce

    $csp->set_nonce($nonce);

    Set the nonce value.

    If value is provided, that value is used. Otherwise, a value is generated.

    A CSP nonce is a random token that is used both in the inline scripts
    and the Content-Security-Policy[-Report-Only] response header.

=cut

sub set_nonce {
    my ( $self, $nonce ) = @_;

    #Koha::Middleware::ContentSecurityPolicy sets an environmental variable
    #We cannot use the L1 cache since it is cleared after the middleware is applied
    if ($nonce) {
        $cached_nonce = $nonce;
    } else {
        my $nonce = Koha::Token->new()->generate( { pattern => '\w{22}' } );
        $cached_nonce = $nonce;
    }
    return 1;
}

1;
