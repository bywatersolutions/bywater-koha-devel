package Koha::REST::Plugin::RateLimit;

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

use Mojo::Base 'Mojolicious::Plugin';

use Digest::SHA qw( sha256_hex );
use Net::Netmask;

use C4::Context;
use Koha::Logger;
use Koha::RateLimit::Counter;

=head1 NAME

Koha::REST::Plugin::RateLimit - Rate limit the REST API per authenticated identity

=head1 SYNOPSIS

    $self->plugin('Koha::REST::Plugin::RateLimit');

=head1 DESCRIPTION

Counts requests per identity in memcached and answers 429 past the configured limit.
The identity is whatever Koha::REST::V1::Auth authenticated, never the client address
unless there is nothing else:

=over

=item * oauth: the API key ( client_id ) behind a bearer token

=item * basic: the patron behind HTTP Basic credentials

=item * session: a logged-in CGISESSID session ( the staff client and the OPAC )

=item * anonymous: an anonymous session, or the client address when there is no session

=item * token: POST /api/v1/oauth/token, per client address, since it runs before authentication

=back

The hook runs around the endpoint action only, so it sees a successful authentication and
never counts failed logins. Off unless enabled in koha-conf.xml:

  <api_rate_limit>
    <enabled>1</enabled>
    <mode>enforce</mode>
    <window>60</window>
    <oauth_limit>600</oauth_limit>
    <session_limit>600</session_limit>
    <basic_limit>300</basic_limit>
    <anonymous_limit>60</anonymous_limit>
    <token_limit>30</token_limit>
    <exempt_ips>127.0.0.1 10.0.0.0/8</exempt_ips>
  </api_rate_limit>

A limit of 0 disables its class. In observe mode every decision is logged and nothing is
refused. Without memcached the limits fail open.

=cut

has enabled     => 0;
has mode        => 'enforce';
has window      => 60;
has limits      => sub { {} };
has exempt_nets => sub { [] };

our %DEFAULT_LIMITS = (
    oauth     => 600,
    session   => 600,
    basic     => 300,
    anonymous => 60,
    token     => 30,
);

use constant KEY_PREFIX => 'api_rl';
use constant TOKEN_PATH => '/api/v1/oauth/token';

=head1 METHODS

=head2 register

Reads the configuration once and hooks around every endpoint action.

=cut

sub register {
    my ( $self, $app ) = @_;

    $self->configure;

    $app->helper( api_rate_limit => sub { return $self } );

    $app->hook(
        around_action => sub {
            my ( $next, $c, $action, $last ) = @_;

            # Only the endpoint action: Auth#under has passed, so failed logins are never
            # counted and the identity is in the stash
            return $next->() unless $last && $self->enabled;
            return if $self->check($c);
            return $next->();
        }
    );
}

=head2 configure

Loads the api_rate_limit block from koha-conf.xml.

=cut

sub configure {
    my ($self) = @_;

    my $config = C4::Context->config('api_rate_limit');
    $config = {} unless ref $config eq 'HASH';

    $self->enabled( $config->{enabled}                             ? 1         : 0 );
    $self->mode( _value( $config->{mode}, 'enforce' ) eq 'observe' ? 'observe' : 'enforce' );
    $self->window( _value( $config->{window}, 60 ) );
    $self->limits( { map { $_ => _value( $config->{"${_}_limit"}, $DEFAULT_LIMITS{$_} ) } keys %DEFAULT_LIMITS } );

    my @exempt_nets;
    foreach my $ip ( grep { length } split /\s+/, _value( $config->{exempt_ips}, q{} ) ) {
        my $mask = Net::Netmask->new2($ip);
        if ($mask) {
            push @exempt_nets, $mask;
        } else {
            $self->logger->warn("api_rate_limit exempt_ips: $Net::Netmask::error");
        }
    }
    $self->exempt_nets( \@exempt_nets );

    return $self;
}

=head2 check

    return if $plugin->check($c);

Counts the request and renders the 429 when it is over its limit. Returns true when a
response was rendered.

=cut

sub check {
    my ( $self, $c ) = @_;

    my $ip = $self->client_ip($c);
    return 0 if $self->is_exempt_ip($ip);

    my ( $class, $id ) = $self->identity( $c, $ip );
    my $limit = $self->limits->{$class} or return 0;

    my $count = Koha::RateLimit::Counter->bump( join( ':', KEY_PREFIX, $class, $id ), $self->window );
    return 0 unless defined $count && $count > $limit;

    return $self->refuse( $c, { class => $class, id => $id, ip => $ip, n => $count, limit => $limit } );
}

=head2 identity

    my ( $class, $id ) = $plugin->identity( $c, $ip );

The limit class and the key the request is counted under.

=cut

sub identity {
    my ( $self, $c, $ip ) = @_;

    my $method = $c->stash('koha.auth_method') // q{};
    my $user   = $c->stash('koha.user');

    if ( $method eq 'oauth' && $c->stash('koha.api_key') ) {
        return ( oauth => $c->stash('koha.api_key')->client_id );
    }
    if ( $method eq 'basic' && $user ) {
        return ( basic => $user->borrowernumber );
    }
    if ( $method eq 'cookie' && defined $c->cookie('CGISESSID') ) {

        # Never put the session id itself in a memcached key or a log line
        my $session = substr( sha256_hex( $c->cookie('CGISESSID') ), 0, 16 );
        return ( $user ? 'session' : 'anonymous' => $session );
    }
    return ( token     => $ip ) if $c->req->url->to_abs->path eq TOKEN_PATH;
    return ( anonymous => $ip );
}

=head2 refuse

Logs the decision and renders the 429, or lets the request through in observe mode.

=cut

sub refuse {
    my ( $self, $c, $details ) = @_;

    $self->logger->warn(
        sprintf(
            "api_rate_limit event=limited mode=%s class=%s id=%s ip=%s method=%s path=%s n=%s limit=%s",
            $self->mode,     $details->{class},          $details->{id}, $details->{ip} // '-',
            $c->req->method, $c->req->url->to_abs->path, $details->{n},  $details->{limit},
        )
    );

    return 0 if $self->mode eq 'observe';

    $c->res->headers->header( 'Retry-After' => $self->window );
    $c->res->headers->cache_control('no-store');
    $c->render( status => 429, json => { error => 'Too many requests', error_code => 'rate_limited' } );
    return 1;
}

=head2 client_ip

The client address, as rewritten by Koha::Middleware::RealIP under Plack.

=cut

sub client_ip {
    my ( $self, $c ) = @_;
    return $c->tx->remote_address;
}

=head2 is_exempt_ip

True when the client address is inside one of the configured exempt networks.

=cut

sub is_exempt_ip {
    my ( $self, $ip ) = @_;

    return 0 unless $ip;

    # Net::Netmask warns when an IPv6 address is matched against an IPv4 block
    my $family = $ip =~ /:/ ? 'IPv6' : 'IPv4';
    foreach my $net ( @{ $self->exempt_nets } ) {
        next     if $net->protocol ne $family;
        return 1 if $net->match($ip);
    }
    return 0;
}

=head2 logger

The api logger, category ratelimit.

=cut

sub logger {
    return Koha::Logger->get( { interface => 'api', category => 'ratelimit' } );
}

=head2 _value

A config value, or the default when the element is missing or empty ( an empty
<element></element> parses as a hashref ).

=cut

sub _value {
    my ( $value, $default ) = @_;
    return defined $value && !ref $value && length $value ? $value : $default;
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
