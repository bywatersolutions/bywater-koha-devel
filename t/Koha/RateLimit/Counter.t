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
use Test::More tests => 5;
use Test::MockModule;

use t::lib::Mocks::Memcached;

use_ok("Koha::RateLimit::Counter");

my $memcached;
my $mock = Test::MockModule->new('Koha::RateLimit::Counter');
$mock->mock( memcached => sub { return $memcached } );

subtest 'bump() tests' => sub {
    plan tests => 7;

    $memcached = t::lib::Mocks::Memcached->new;

    is( Koha::RateLimit::Counter->bump( 'k', 45 ),     1,  'first bump creates the counter at 1' );
    is( $memcached->{ttl}{k},                          45, 'the creator sets the lifetime' );
    is( Koha::RateLimit::Counter->bump( 'k', 45 ),     2,  'second bump increments' );
    is( Koha::RateLimit::Counter->bump( 'k', 45 ),     3,  'third bump increments again' );
    is( Koha::RateLimit::Counter->bump( 'other', 45 ), 1,  'another key has its own counter' );
    is( $memcached->{store}{k},                        3,  'the first key is untouched by the second' );

    # Another worker created the key between our failed incr and our add
    my $racing = Test::MockModule->new('t::lib::Mocks::Memcached');
    $racing->mock(
        add => sub {
            my ( $self, $key ) = @_;
            $self->{store}{$key} = 7;
            return 0;
        }
    );
    is( Koha::RateLimit::Counter->bump( 'raced', 45 ), 8, 'losing the creation race still counts this request' );
};

subtest 'release() tests' => sub {
    plan tests => 3;

    $memcached = t::lib::Mocks::Memcached->new;
    Koha::RateLimit::Counter->bump( 'inflight', 120 ) for 1 .. 2;
    Koha::RateLimit::Counter->release('inflight');
    is( $memcached->{store}{inflight}, 1, 'release decrements' );
    Koha::RateLimit::Counter->release('inflight');
    Koha::RateLimit::Counter->release('inflight');
    is( $memcached->{store}{inflight},                0,     'release stops at zero' );
    is( Koha::RateLimit::Counter->release('missing'), undef, 'releasing an unknown key is harmless' );
};

subtest 'fail open' => sub {
    plan tests => 4;

    $memcached = undef;
    is( Koha::RateLimit::Counter->bump( 'k', 60 ), undef, 'no memcached: bump returns undef' );
    is( Koha::RateLimit::Counter->release('k'),    undef, 'no memcached: release returns undef' );

    $memcached = t::lib::Mocks::Memcached->new( fail => 1 );
    is( Koha::RateLimit::Counter->bump( 'k', 60 ), undef, 'memcached errors: bump returns undef' );
    is( Koha::RateLimit::Counter->release('k'),    undef, 'memcached errors: release returns undef' );
};
