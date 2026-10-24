package Koha::RateLimit::Counter;

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

use Koha::Caches;

=head1 NAME

Koha::RateLimit::Counter - Expiring request counters in memcached

=head1 SYNOPSIS

    my $count = Koha::RateLimit::Counter->bump( "api_rl:oauth:$client_id", 60 );
    Koha::RateLimit::Counter->release('botguard:inflight');

=head1 DESCRIPTION

Shared by Koha::Middleware::BotGuard and Koha::REST::Plugin::RateLimit. Counters are
plain memcached keys so every starman worker sees the same numbers. Every method
returns undef when there is no memcached or memcached fails, so callers fail open.

=head1 METHODS

=head2 memcached

The Cache::Memcached::Fast::Safe handle Koha already uses, or undef when there is none.

=cut

sub memcached {
    return Koha::Caches->get_instance->memcached_cache;
}

=head2 bump

    my $count = Koha::RateLimit::Counter->bump( $key, $ttl );

Increments a counter, creating it with the given lifetime on first use.

=cut

sub bump {
    my ( $class, $key, $ttl ) = @_;

    my $memcached = $class->memcached or return;

    return eval {
        my $value = $memcached->incr($key);
        return unless defined $value;
        return $value if $value;

        # The key doesn't exist yet. Only the creator sets the expiry, so a leaked count
        # expires on its own instead of being refreshed forever.
        return 1 if $memcached->add( $key, 1, $ttl );
        my $retry = $memcached->incr($key);
        return $retry ? $retry : 1;
    };
}

=head2 release

    Koha::RateLimit::Counter->release($key);

Decrements a counter once an in-flight request finishes.

=cut

sub release {
    my ( $class, $key ) = @_;

    my $memcached = $class->memcached or return;

    eval { $memcached->decr($key) };
    return;
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
