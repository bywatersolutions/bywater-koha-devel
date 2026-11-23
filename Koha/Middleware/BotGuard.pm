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

use File::Basename qw( dirname );
use File::Slurp    qw( read_file );
use File::Spec;
use JSON qw( decode_json );
use Net::Netmask;
use Plack::Util::Accessor
    qw( enabled mode rate_limit authenticated_rate_limit rate_window max_concurrent issue_limit pow_difficulty exempt_nets heavy crawler_user_agents crawler_nets );

use Koha::BotGuard::ProofOfWork;
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
page's JavaScript solves a proof of work puzzle ( Koha::BotGuard::ProofOfWork ), sends the
solution to /cgi-bin/koha/svc/opac_trust, which sets the cookie, and reloads. No CGI script
is compiled or run for the refused request.

=item * A request with a cookie is counted in memcached and gets a 429 once it exceeds
rate_limit heavy requests per rate_window seconds.

=item * Anonymous heavy requests in flight per instance are capped at max_concurrent, with
a 503 beyond that, so a scrape can never take every starman worker.

=item * Cookies issued to logged-in patrons by C4::Auth are never challenged or capped and
are limited by the much higher authenticated_rate_limit instead.

=back

The feature is off unless enabled in koha-conf.xml:

  <opac_bot_guard>
    <enabled>1</enabled>
    <mode>enforce</mode>
    <secret></secret>
    <cookie_ttl>2592000</cookie_ttl>
    <rate_limit>60</rate_limit>
    <authenticated_rate_limit>600</authenticated_rate_limit>
    <rate_window>60</rate_window>
    <max_concurrent>4</max_concurrent>
    <issue_limit>30</issue_limit>
    <pow_difficulty>18</pow_difficulty>
    <exempt_ips>127.0.0.1 10.0.0.0/8</exempt_ips>
    <heavy_scripts></heavy_scripts>
    <crawler_user_agents>Googlebot|bingbot|Applebot|DuckDuckBot</crawler_user_agents>
    <crawler_ranges_file></crawler_ranges_file>
  </opac_bot_guard>

Search engine crawlers don't keep cookies either, so a request whose user agent contains one
of crawler_user_agents and whose address is inside the ranges that search engine publishes
( Koha/BotGuard/verified_crawlers.json, rebuilt by misc/maintenance/update_verified_crawler_ranges.pl )
is never challenged or rate limited. It still counts toward max_concurrent.

In observe mode every decision is logged but nothing is refused. Search feeds ( opac-search.pl
with format=rss, atom or opensearchdescription ) and public list feeds ( opac-shelves.pl with
rss=1 ) are never challenged, since feed readers don't keep cookies, but they are rate limited
per client address and count toward max_concurrent. Without memcached the limits fail open;
the challenge needs no state and keeps working.

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
    opac-basket.pl
    opac-downloadcart.pl
    opac-downloadshelf.pl
    svc/shelfbrowser.pl
);

our $DEFAULT_CRAWLER_RANGES_FILE =
    File::Spec->catfile( dirname( dirname(__FILE__) ), 'BotGuard', 'verified_crawlers.json' );

use constant DEFAULT_CRAWLER_USER_AGENTS => 'Googlebot|bingbot|Applebot|DuckDuckBot';
use constant ISSUE_PATH                  => '/svc/opac_trust';
use constant INFLIGHT_KEY                => 'botguard:inflight';
use constant INFLIGHT_TTL                => 120;
use constant ISSUE_WINDOW                => 60;
use constant CAPPED_LOG_INTERVAL         => 10;

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
    var key = 'koha_trust_attempt', now = Date.now(), attempt = null, stored = null;

    // sessionStorage throws when cookies are blocked, so window.name keeps the count then
    try { stored = sessionStorage.getItem(key); } catch (e) {
        stored = window.name.indexOf(key + '=') === 0 ? window.name.slice(key.length + 1) : null;
    }
    try { attempt = JSON.parse(stored || 'null'); } catch (e) {}
    if (!attempt || now - attempt.t > 60000) { attempt = { n: 0, t: now }; }
    function failed() {
        document.getElementById('spinner').hidden = true;
        document.getElementById('status').hidden = true;
        document.getElementById('failed').hidden = false;
    }
    if (attempt.n >= 3) { return failed(); }
    attempt.n++;
    try { sessionStorage.setItem(key, JSON.stringify(attempt)); } catch (e) {
        window.name = key + '=' + JSON.stringify(attempt);
    }
    var delay = 250;
    if (navigator.webdriver) { delay += 10000; }
    if (!navigator.languages || !navigator.languages.length) { delay += 5000; }
    var puzzle = '__PUZZLE__', difficulty = __DIFFICULTY__;
    function issue(query) {
        fetch('/cgi-bin/koha/svc/opac_trust' + query, { credentials: 'same-origin', cache: 'no-store' })
            .then(function (r) {
                if (!r.ok) { return failed(); }

                // replace() doesn't send a POST again, but only reload() reloads a URL with a #fragment
                if (location.hash) { location.reload(); } else { location.replace(location.href); }
            })
            .catch(failed);
    }

    // The search runs in a worker so it isn't throttled in a background tab and doesn't block the page
    function solver() {
        var K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
        var w = new Uint32Array(64), h = new Uint32Array(8);
        function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }
        function sha256(str) {
            var len = str.length, i;
            var bytes = new Uint8Array(((len + 9 + 63) >> 6) << 6);
            for (i = 0; i < len; i++) { bytes[i] = str.charCodeAt(i); }
            bytes[len] = 0x80;
            var view = new DataView(bytes.buffer);
            view.setUint32(bytes.length - 4, len * 8, false);
            h.set([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
            for (var offset = 0; offset < bytes.length; offset += 64) {
                for (i = 0; i < 16; i++) { w[i] = view.getUint32(offset + i * 4, false); }
                for (i = 16; i < 64; i++) {
                    var s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
                    var s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
                    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
                }
                var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
                for (i = 0; i < 64; i++) {
                    var t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) >>> 0;
                    var t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
                    hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
                }
                h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
            }
            return h;
        }
        function leadingZeroBits(words) {
            for (var i = 0, bits = 0; i < 8; i++, bits += 32) {
                if (words[i] !== 0) { return bits + Math.clz32(words[i]); }
            }
            return 256;
        }
        self.onmessage = function (event) {
            for (var counter = 0; ; counter++) {
                if (leadingZeroBits(sha256(event.data.puzzle + '.' + counter)) >= event.data.difficulty) {
                    return self.postMessage(counter);
                }
            }
        };
    }
    setTimeout(function () {
        if (!difficulty) { return issue(''); }
        try {
            var worker = new Worker(URL.createObjectURL(new Blob(['(' + solver.toString() + ')()'], { type: 'text/javascript' })));
            worker.onmessage = function (event) { issue('?pow=' + puzzle + '&counter=' + event.data); };
            worker.postMessage({ puzzle: puzzle, difficulty: difficulty });
        } catch (e) { failed(); }
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
    $self->rate_limit( $config->{rate_limit}                             // 60 );
    $self->authenticated_rate_limit( $config->{authenticated_rate_limit} // 600 );
    $self->rate_window( $config->{rate_window}                           // 60 );
    $self->max_concurrent( $config->{max_concurrent}                     // 4 );
    $self->issue_limit( $config->{issue_limit}                           // 30 );
    $self->pow_difficulty( $config->{pow_difficulty}                     // 18 );

    my @heavy_scripts =
        $config->{heavy_scripts}
        ? grep { length } split /\s+/, $config->{heavy_scripts}
        : @DEFAULT_HEAVY_SCRIPTS;
    $self->heavy( { map { $_ => 1 } @heavy_scripts } );

    my @exempt_nets;
    foreach my $ip ( grep { length } split /\s+/, $config->{exempt_ips} // q{} ) {
        my $mask = Net::Netmask->new2($ip);
        if ($mask) {
            push @exempt_nets, $mask;
        } else {
            $self->logger->warn("opac_bot_guard exempt_ips: $Net::Netmask::error");
        }
    }
    $self->exempt_nets( \@exempt_nets );

    my $crawler_user_agents = $config->{crawler_user_agents} // DEFAULT_CRAWLER_USER_AGENTS;
    my @crawler_user_agents = $crawler_user_agents ? grep { length } split /\|/, $crawler_user_agents : ();
    my @crawler_nets;
    if ( $enabled && @crawler_user_agents ) {
        my $file   = $config->{crawler_ranges_file} // $DEFAULT_CRAWLER_RANGES_FILE;
        my $ranges = eval { decode_json( read_file($file) )->{ranges} };
        if ( ref $ranges eq 'HASH' ) {
            @crawler_nets = map { Net::Netmask->new2($_) || () } map { @$_ } values %$ranges;
        } else {
            $self->logger->warn("opac_bot_guard could not read crawler ranges from $file, crawlers will be challenged");
        }
    }
    my $crawler_pattern = join '|', map { quotemeta } @crawler_user_agents;
    $self->crawler_user_agents( @crawler_nets ? qr/$crawler_pattern/ : undef );
    $self->crawler_nets( \@crawler_nets );
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

    my $trust   = Koha::BotGuard::TrustCookie->verify( $self->cookie_value($env) );
    my $feed    = !$trust && $self->is_feed( $env, $script );
    my $crawler = !$trust && !$feed && $self->is_verified_crawler($env);

    if ( !$trust && !$feed && !$crawler ) {
        my $refusal = $self->refuse( $env, 'challenge', $trust, $self->challenge_response );
        return $refusal if $refusal;
    }

    # No memcached means no counters, so the limits fail open
    my $memcached = Koha::RateLimit::Counter->memcached;

    # Logged in patrons get a much higher limit, and feed readers without a cookie are counted per address
    my $authenticated = $trust && $trust->{kind} eq 'authenticated';
    my ( $key, $limit ) =
          $authenticated ? ( "botguard:rl:$trust->{nonce}", $self->authenticated_rate_limit )
        : $trust         ? ( "botguard:rl:$trust->{nonce}", $self->rate_limit )
        : $feed          ? ( 'botguard:feed:' . ( $env->{REMOTE_ADDR} // q{} ), $self->rate_limit )
        :                  ();

    if ( $memcached && $key && $limit ) {
        my $count = Koha::RateLimit::Counter->bump( $key, $self->rate_window );
        if ( defined $count && $count > $limit ) {
            my $refusal = $self->refuse(
                $env, 'limited', $trust, $self->too_many_response( $self->rate_window ),
                { n => $count, limit => $limit }
            );
            return $refusal if $refusal;
        }
    }

    return $self->app->($env) if $authenticated;

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

Handles GET /svc/opac_trust?pow=<puzzle>&counter=<solution>, which sets an anonymous trust cookie.

=cut

sub issue_response {
    my ( $self, $env ) = @_;

    return [ 405, [ 'Allow' => 'GET', 'Cache-Control' => 'no-store' ], [] ]
        unless ( $env->{REQUEST_METHOD} // q{} ) eq 'GET';

    my @headers = ( 'Cache-Control' => 'no-store, private' );

    # A client that already holds a valid cookie keeps it, so a repeat call can't reset a budget or downgrade a login
    return [ 204, \@headers, [] ] if Koha::BotGuard::TrustCookie->verify( $self->cookie_value($env) );

    # The solved puzzle's nonce becomes the cookie's nonce, so a replayed solution gets the same budget, not a new one
    my $nonce;
    if ( $self->pow_difficulty ) {
        my $query     = $env->{QUERY_STRING} // q{};
        my ($puzzle)  = $query =~ /(?:^|&)pow=([^&]*)/;
        my ($counter) = $query =~ /(?:^|&)counter=([^&]*)/;
        $nonce = Koha::BotGuard::ProofOfWork->verify( $puzzle, $counter, $self->pow_difficulty );
        unless ($nonce) {
            my $refusal = $self->refuse( $env, 'pow_required', undef, $self->pow_required_response );
            return $refusal if $refusal;
        }
    }

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
    push @headers,
        'Set-Cookie' =>
        Koha::BotGuard::TrustCookie->set_cookie_header( 'anonymous', { secure => $secure, nonce => $nonce } );
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
    return $self->ip_in_nets( $ip, $self->exempt_nets );
}

=head2 is_verified_crawler

True when the user agent claims to be a search engine crawler and the client address is inside
the ranges that search engine publishes, so a spoofed user agent gets the challenge like anyone else.

=cut

sub is_verified_crawler {
    my ( $self, $env ) = @_;

    my $user_agents = $self->crawler_user_agents or return 0;
    return 0 unless ( $env->{HTTP_USER_AGENT} // q{} ) =~ $user_agents;
    return $self->ip_in_nets( $env->{REMOTE_ADDR}, $self->crawler_nets );
}

=head2 ip_in_nets

    my $inside = $self->ip_in_nets( $ip, $nets );

True when the address is inside one of the Net::Netmask blocks.

=cut

sub ip_in_nets {
    my ( $self, $ip, $nets ) = @_;

    return 0 unless $ip;

    # Net::Netmask warns when an IPv6 address is matched against an IPv4 block
    my $family = $ip =~ /:/ ? 'IPv6' : 'IPv4';
    foreach my $net (@$nets) {
        next     if $net->protocol ne $family;
        return 1 if $net->match($ip);
    }
    return 0;
}

=head2 is_feed

    my $feed = $self->is_feed( $env, $script );

True for the requests feed readers make without cookies: search results as RSS, Atom or
OpenSearch description from opac-search.pl, and public list RSS from opac-shelves.pl. Only
those scripts serve feeds, so a format parameter on any other script is just a page.

=cut

sub is_feed {
    my ( $self, $env, $script ) = @_;

    my $query = $env->{QUERY_STRING} // q{};
    if ( $script eq 'opac-search.pl' ) {

        # The script reads the first format parameter, so so do we
        my ($format) = $query =~ /(?:^|&)format=([^&]*)/;
        return $format && $format =~ /^(?:rss2?|atom|opensearchdescription)$/ ? 1 : 0;
    }
    if ( $script eq 'opac-shelves.pl' ) {
        my ($rss) = $query =~ /(?:^|&)rss=([^&]*)/;
        return $rss ? 1 : 0;
    }
    return 0;
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

    # Challenges and missing proofs of work are too frequent to log unless we are sizing the impact. A
    # scrape would log every refusal too, so a limit is logged once per counter window and the cap once
    # every few seconds.
    my $log =
          $event eq 'challenge' || $event eq 'pow_required' ? $observe
        : $event eq 'capped'
        ? ( Koha::RateLimit::Counter->bump( 'botguard:log:capped', CAPPED_LOG_INTERVAL ) // 1 ) == 1
        : ( $details->{n} // 0 ) == ( $details->{limit} // 0 ) + 1;

    if ($log) {
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

The page served instead of a heavy script when there is no valid cookie, with a fresh puzzle.

=cut

sub challenge_response {
    my ($self) = @_;

    my $difficulty = $self->pow_difficulty;
    my $puzzle     = $difficulty ? Koha::BotGuard::ProofOfWork->issue($difficulty) // q{} : q{};
    my $html       = CHALLENGE_HTML;
    $html =~ s/__PUZZLE__/$puzzle/;
    $html =~ s/__DIFFICULTY__/$difficulty/;

    return [
        200,
        [
            'Content-Type'    => 'text/html; charset=utf-8',
            'Cache-Control'   => 'no-store, private',
            'Vary'            => 'Cookie',
            'X-Robots-Tag'    => 'noindex',
            'X-Koha-BotGuard' => 'challenge',
        ],
        [$html]
    ];
}

=head2 pow_required_response

A 422 for an issue request without a solved puzzle. Not a 400, since ErrorDocument in
plack.psgi would replace a 400 with a full OPAC error page.

=cut

sub pow_required_response {
    my ($self) = @_;

    return [
        422,
        [
            'Content-Type'    => 'application/json',
            'Cache-Control'   => 'no-store, private',
            'X-Koha-BotGuard' => 'proof_of_work_required',
        ],
        ['{"error":"proof_of_work_required"}']
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
