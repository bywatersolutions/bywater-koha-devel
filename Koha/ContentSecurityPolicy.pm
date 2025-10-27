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
use Koha::Cache::Memory::Lite;
use Koha::Token;

use Koha::Exceptions::Config;

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

    $self->nonce( $params->{nonce} );
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

    my $interface //= $args->{interface} || C4::Context->interface;

    my $conf_csp = $self->{config}->get('content_security_policy');

    Koha::Exceptions::Config::MissingEntry->throw( error => 'Missing request content_security_policy csp_header_value' )
        unless exists $conf_csp->{$interface}->{csp_mode};

    return 'Content-Security-Policy-Report-Only' if $conf_csp->{$interface}->{csp_mode} eq 'report-only';
    return 'Content-Security-Policy'             if $conf_csp->{$interface}->{csp_mode} eq 'enabled';

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

    Throws Koha::Exceptions::Config::MissingEntry is CSP property "csp_header_value" is missing in KOHA_CONF

=cut

sub header_value {
    my ( $self, $args ) = @_;

    my $interface //= $args->{interface} || C4::Context->interface;

    my $conf_csp = $self->{config}->get('content_security_policy');

    Koha::Exceptions::Config::MissingEntry->throw( error => 'Missing request content_security_policy csp_header_value' )
        unless exists $conf_csp->{$interface}->{csp_header_value};

    my $csp_header_value = $conf_csp->{$interface}->{csp_header_value};
    my $csp_nonce        = $self->nonce;

    $csp_header_value =~ s/_CSP_NONCE_/$csp_nonce/g;

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
    my $interface //= $args->{interface} || C4::Context->interface;

    my $conf_csp = $self->{config}->get('content_security_policy');

    return 0 if $interface ne 'opac' && $interface ne 'intranet';

    return 0 unless exists $conf_csp->{$interface}->{csp_mode};
    return 1
        if $conf_csp->{$interface}->{csp_mode} eq 'report-only'
        or $conf_csp->{$interface}->{csp_mode} eq 'enabled';
    return 0;
}

=head2 nonce

    $csp->nonce();

    Generates and returns the nonce.

    $csp->nonce($nonce);

    Sets and returns the nonce.

    A CSP nonce is a random token that is used both in the inline scripts
    and the Content-Security-Policy[-Report-Only] response header.

=cut

sub nonce {
    my ( $self, $nonce ) = @_;
    my $cache = Koha::Cache::Memory::Lite->new;

    if ($nonce) {
        $cache->set_in_cache( 'CSP-NONCE', $nonce );
        $self->{nonce} = $nonce;
        return $self->{nonce};
    }

    if ( $nonce = $cache->get_from_cache('CSP-NONCE') ) {
        $self->{nonce} = $nonce;
        return $self->{nonce};
    }

    unless ( $self->{nonce} ) {
        $nonce = Koha::Token->new()->generate( { pattern => '\w{10}' } );
        $self->{nonce} = $nonce;
    }

    $cache->set_in_cache( 'CSP-NONCE', $self->{nonce} );

    return $self->{nonce};
}

1;
