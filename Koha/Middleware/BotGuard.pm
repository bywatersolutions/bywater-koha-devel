package Koha::Middleware::BotGuard;

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

use parent qw(Plack::Middleware);

use Net::Netmask;
use Plack::Util::Accessor qw( enabled mode rate_limit rate_window max_concurrent issue_limit exempt_nets heavy );

use Koha::BotGuard::TrustCookie;
use Koha::Logger;
use Koha::RateLimit::Counter;

=head1 NAME

Koha::Middleware::BotGuard - Challenge cookie-less clients on heavy OPAC pages and cap anonymous load

=head1 SYNOPSIS

  builder {
      ...
      enable "+Koha::Middleware::BotGuard";
      ...
  }

=head1 DESCRIPTION

Scrapers spread over thousands of residential IP addresses walk the expensive OPAC
pages ( search results, record details ) without keeping cookies, and per-IP rate
limits in front of Koha punish patrons behind a shared branch or carrier NAT instead.
This middleware keys everything on a signed trust cookie ( Koha::BotGuard::TrustCookie )
rather than the client address:

=over

=item * A heavy request without a valid cookie gets a small static challenge page. The
page's JavaScript fetches /cgi-bin/koha/svc/opac_trust, which sets the cookie, and reloads.
No CGI script is compiled or run for the refused request.

=item * A request with a cookie is counted in memcached and gets a 429 once it exceeds
rate_limit heavy requests per rate_window seconds.

=item * Anonymous heavy requests in flight per instance are capped at max_concurrent, with
a 503 beyond that, so a scrape can never take every starman worker.

=item * Cookies issued to logged-in patrons by C4::Auth bypass both limits.

=back

The feature is off unless enabled in koha-conf.xml:

  <opac_bot_guard>
    <enabled>1</enabled>
    <mode>enforce</mode>
    <secret></secret>
    <cookie_ttl>2592000</cookie_ttl>
    <rate_limit>60</rate_limit>
    <rate_window>60</rate_window>
    <max_concurrent>4</max_concurrent>
    <issue_limit>30</issue_limit>
    <exempt_ips>127.0.0.1 10.0.0.0/8</exempt_ips>
    <heavy_scripts></heavy_scripts>
  </opac_bot_guard>

In observe mode every decision is logged but nothing is refused. Feed requests
( format=rss, atom, opensearchdescription ) are never challenged or rate limited, but
they do count toward max_concurrent. Without memcached the limits fail open; the
challenge needs no state and keeps working.

=cut

our @DEFAULT_HEAVY_SCRIPTS = qw(
    opac-search.pl
    opac-detail.pl
    opac-MARCdetail.pl
    opac-ISBDdetail.pl
    opac-showmarc.pl
    opac-export.pl
    opac-authoritiesdetail.pl
    opac-authorities-home.pl
    opac-browse.pl
    opac-shelves.pl
    svc/shelfbrowser.pl
);

use constant ISSUE_PATH   => '/svc/opac_trust';
use constant INFLIGHT_KEY => 'botguard:inflight';
use constant INFLIGHT_TTL => 120;
use constant ISSUE_WINDOW => 60;

use constant REFUSED_HTML => <<'HTML';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>%s</title>
<style>body{font-family:sans-serif;margin:3em auto;max-width:40em;padding:0 1em;text-align:center}</style>
</head>
<body>
<h1>%s</h1>
<p>%s</p>
</body>
</html>
HTML

use constant CHALLENGE_HTML => <<'HTML';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Loading the catalog</title>
<style>
body{font-family:sans-serif;margin:3em auto;max-width:40em;padding:0 1em;text-align:center}
.spinner{width:48px;height:48px;margin:2em auto;border:5px solid #ddd;border-top-color:#555;border-radius:50%;animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
[hidden]{display:none}
</style>
</head>
<body>
<div class="spinner" id="spinner"></div>
<p id="status" role="status" aria-live="polite">Checking your browser before loading the catalog.</p>
<p id="failed" hidden>We could not verify your browser. Please make sure cookies and JavaScript are enabled, then <a href="">reload the page</a>.</p>
<noscript><p>JavaScript is required to search the catalog.</p></noscript>
<script>
(function () {
    var key = 'koha_trust_attempt', now = Date.now(), attempt = null;
    try { attempt = JSON.parse(sessionStorage.getItem(key) || 'null'); } catch (e) {}
    if (!attempt || now - attempt.t > 60000) { attempt = { n: 0, t: now }; }
    function failed() {
        document.getElementById('spinner').hidden = true;
        document.getElementById('status').hidden = true;
        document.getElementById('failed').hidden = false;
    }
    if (attempt.n >= 3) { return failed(); }
    attempt.n++;
    try { sessionStorage.setItem(key, JSON.stringify(attempt)); } catch (e) {}
    var delay = 250;
    if (navigator.webdriver) { delay += 10000; }
    if (!navigator.languages || !navigator.languages.length) { delay += 5000; }
    setTimeout(function () {
        fetch('/cgi-bin/koha/svc/opac_trust', { credentials: 'same-origin', cache: 'no-store' })
            .then(function (r) { if (r.ok) { location.reload(); } else { failed(); } })
            .catch(failed);
    }, delay);
})();
</script>
</body>
</html>
HTML

=head1 METHODS

=head2 prepare_app

Reads the koha-conf.xml configuration once at Plack startup.

=cut

sub prepare_app {
    my ($self) = @_;

    my $config = Koha::BotGuard::TrustCookie->config;

    my $enabled = $config->{enabled} ? 1 : 0;
    if ( $enabled && !Koha::BotGuard::TrustCookie->secret ) {
        $self->logger->warn(
            "opac_bot_guard is enabled but neither <secret> nor api_secret_passphrase is set, disabling it");
        $enabled = 0;
    }
    $self->enabled($enabled);
    $self->mode( ( $config->{mode} // q{} ) eq 'observe' ? 'observe' : 'enforce' );
    $self->rate_limit( $config->{rate_limit}         // 60 );
    $self->rate_window( $config->{rate_window}       // 60 );
    $self->max_concurrent( $config->{max_concurrent} // 4 );
    $self->issue_limit( $config->{issue_limit}       // 30 );

    my @heavy_scripts =
        ref $config->{heavy_scripts} || !$config->{heavy_scripts}
        ? @DEFAULT_HEAVY_SCRIPTS
        : grep { length } split /\s+/, $config->{heavy_scripts};
    $self->heavy( { map { $_ => 1 } @heavy_scripts } );

    my @exempt_nets;
    my $exempt_ips = ref $config->{exempt_ips} ? q{} : $config->{exempt_ips} // q{};
    foreach my $ip ( grep { length } split /\s+/, $exempt_ips ) {
        my $mask = Net::Netmask->new2($ip);
        if ($mask) {
            push @exempt_nets, $mask;
        } else {
            $self->logger->warn("opac_bot_guard exempt_ips: $Net::Netmask::error");
        }
    }
    $self->exempt_nets( \@exempt_nets );
}

=head2 call

Admits, challenges or refuses the request.

=cut

sub call {
    my ( $self, $env ) = @_;

    my $path = $env->{PATH_INFO} // q{};

    unless ( $self->enabled ) {

        # Answer a stale challenge page's callback so it reloads instead of looping
        return [ 204, [ 'Cache-Control' => 'no-store' ], [] ] if $path eq ISSUE_PATH;
        return $self->app->($env);
    }

    # ErrorDocument is rendering an error page for a request that was already admitted
    return $self->app->($env) if $env->{'psgix.errordocument.SCRIPT_NAME'};

    return $self->issue_response($env) if $path eq ISSUE_PATH;

    my $script = $self->script_for_path($path);
    return $self->app->($env) unless $script && $self->heavy->{$script};
    return $self->app->($env) if $self->is_exempt_ip( $env->{REMOTE_ADDR} );

    my $trust = Koha::BotGuard::TrustCookie->verify( $self->cookie_value($env) );
    return $self->app->($env) if $trust && $trust->{kind} eq 'authenticated';

    if ( !$trust && !$self->is_feed($env) ) {
        my $refusal = $self->refuse( $env, 'challenge', $trust, $self->challenge_response );
        return $refusal if $refusal;
    }

    # No memcached means no counters, so the limits fail open
    my $memcached = Koha::RateLimit::Counter->memcached;

    if ( $memcached && $trust && $self->rate_limit ) {
        my $count = Koha::RateLimit::Counter->bump( "botguard:rl:$trust->{nonce}", $self->rate_window );
        if ( defined $count && $count > $self->rate_limit ) {
            my $refusal = $self->refuse(
                $env, 'limited', $trust, $self->too_many_response( $self->rate_window ),
                { n => $count, limit => $self->rate_limit }
            );
            return $refusal if $refusal;
        }
    }

    my $counted = 0;
    if ( $memcached && $self->max_concurrent ) {
        my $inflight = Koha::RateLimit::Counter->bump( INFLIGHT_KEY, INFLIGHT_TTL );
        if ( defined $inflight ) {
            $counted = 1;
            if ( $inflight > $self->max_concurrent ) {
                my $refusal = $self->refuse(
                    $env, 'capped', $trust, $self->busy_response,
                    { n => $inflight, limit => $self->max_concurrent }
                );
                if ($refusal) {
                    Koha::RateLimit::Counter->release(INFLIGHT_KEY);
                    return $refusal;
                }
            }
        }
    }

    my $response = eval { $self->app->($env) };
    my $error    = $@;
    Koha::RateLimit::Counter->release(INFLIGHT_KEY) if $counted;
    die $error                                      if $error;
    return $response;
}

=head2 issue_response

Handles GET /svc/opac_trust, which sets an anonymous trust cookie.

=cut

sub issue_response {
    my ( $self, $env ) = @_;

    return [ 405, [ 'Allow' => 'GET', 'Cache-Control' => 'no-store' ], [] ]
        unless ( $env->{REQUEST_METHOD} // q{} ) eq 'GET';

    my @headers = ( 'Cache-Control' => 'no-store, private' );

    # A client that already holds a valid cookie keeps it, so a repeat call can't reset a budget or downgrade a login
    return [ 204, \@headers, [] ] if Koha::BotGuard::TrustCookie->verify( $self->cookie_value($env) );

    my $memcached = Koha::RateLimit::Counter->memcached;
    if ( $memcached && $self->issue_limit ) {
        my $count = Koha::RateLimit::Counter->bump( 'botguard:issue:' . ( $env->{REMOTE_ADDR} // q{} ), ISSUE_WINDOW );
        if ( defined $count && $count > $self->issue_limit ) {
            my $refusal = $self->refuse(
                $env, 'issue_limited', undef, $self->too_many_response(ISSUE_WINDOW),
                { n => $count, limit => $self->issue_limit }
            );
            return $refusal if $refusal;
        }
    }

    my $secure = ( $env->{'psgi.url_scheme'} // q{} ) eq 'https';
    push @headers, 'Set-Cookie' => Koha::BotGuard::TrustCookie->set_cookie_header( 'anonymous', { secure => $secure } );
    return [ 204, \@headers, [] ];
}

=head2 script_for_path

    my $script = $self->script_for_path($path);

The OPAC script a PATH_INFO resolves to, e.g. 'opac-search.pl' or 'svc/shelfbrowser.pl'.

=cut

sub script_for_path {
    my ( $self, $path ) = @_;

    return unless defined $path && length $path;

    # Apache proxies /cgi-bin/koha to the /opac mount, so accept either shape
    $path =~ s{^/(?:cgi-bin/koha|opac)(?=/)}{};

    # Plack::App::CGIBin walks the segments until it finds a script and hands the rest over as
    # path info, so '/opac-search.pl/x' and '//opac-search.pl' both run opac-search.pl
    my @segments = grep { length && $_ ne '.' } split m{/}, $path;
    return unless @segments;
    return $segments[0] eq 'svc' && defined $segments[1] ? "svc/$segments[1]" : $segments[0];
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

=head2 is_feed

True for RSS, Atom and OpenSearch description requests, which feed readers fetch without cookies.

=cut

sub is_feed {
    my ( $self, $env ) = @_;

    # The scripts read the first format parameter, so so do we
    my ($format) = ( $env->{QUERY_STRING} // q{} ) =~ /(?:^|&)format=([^&]*)/;
    return $format && $format =~ /^(?:rss2?|atom|opensearchdescription)$/ ? 1 : 0;
}

=head2 cookie_value

The raw KOHA_TRUST cookie value from the request, if any.

=cut

sub cookie_value {
    my ( $self, $env ) = @_;

    my ($value) = ( $env->{HTTP_COOKIE} // q{} ) =~ /(?:^|;\s*)KOHA_TRUST=([^;]*)/;
    return $value;
}

=head2 logger

The opac logger, category botguard.

=cut

sub logger {
    return Koha::Logger->get( { interface => 'opac', category => 'botguard' } );
}

=head2 refuse

    my $response = $self->refuse( $env, $event, $trust, $response, $details );

Logs the decision and returns the response to send, or undef in observe mode so the
request goes through anyway.

=cut

sub refuse {
    my ( $self, $env, $event, $trust, $response, $details ) = @_;

    my $observe = $self->mode eq 'observe';

    # Challenges are too frequent to log one by one unless we are sizing the impact
    if ( $event ne 'challenge' || $observe ) {
        $self->logger->warn(
            sprintf(
                "botguard event=%s mode=%s ip=%s method=%s path=%s cid=%s n=%s limit=%s",
                $event, $self->mode,
                $env->{REMOTE_ADDR}    // '-',
                $env->{REQUEST_METHOD} // '-',
                $env->{PATH_INFO}      // '-',
                $trust ? substr( $trust->{nonce}, 0, 8 ) : '-',
                $details->{n}     // '-',
                $details->{limit} // '-',
            )
        );
    }

    return $observe ? undef : $response;
}

=head2 challenge_response

The static page served instead of a heavy script when there is no valid cookie.

=cut

sub challenge_response {
    my ($self) = @_;

    return [
        200,
        [
            'Content-Type'    => 'text/html; charset=utf-8',
            'Cache-Control'   => 'no-store, private',
            'Vary'            => 'Cookie',
            'X-Robots-Tag'    => 'noindex',
            'X-Koha-BotGuard' => 'challenge',
        ],
        [CHALLENGE_HTML]
    ];
}

=head2 too_many_response

A 429 with Retry-After for a client over its budget.

=cut

sub too_many_response {
    my ( $self, $retry_after ) = @_;

    return [
        429,
        [
            'Content-Type'    => 'text/html; charset=utf-8',
            'Cache-Control'   => 'no-store',
            'Retry-After'     => $retry_after,
            'X-Koha-BotGuard' => 'limited',
        ],
        [ sprintf( REFUSED_HTML, ('Too many requests') x 2, 'Please wait a minute and try again.' ) ]
    ];
}

=head2 busy_response

A 503 with Retry-After when the anonymous in-flight cap is reached.

=cut

sub busy_response {
    my ($self) = @_;

    return [
        503,
        [
            'Content-Type'    => 'text/html; charset=utf-8',
            'Cache-Control'   => 'no-store',
            'Retry-After'     => 2,
            'X-Koha-BotGuard' => 'capped',
        ],
        [
            sprintf(
                REFUSED_HTML, ('Catalog busy') x 2, 'The catalog is busy right now. Please try again in a moment.'
            )
        ]
    ];
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
