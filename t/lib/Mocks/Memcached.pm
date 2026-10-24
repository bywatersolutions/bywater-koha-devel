package t::lib::Mocks::Memcached;

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

=head1 NAME

t::lib::Mocks::Memcached - In-memory stand-in for the Cache::Memcached::Fast counter methods

=head1 SYNOPSIS

    my $memcached = t::lib::Mocks::Memcached->new;
    my $broken    = t::lib::Mocks::Memcached->new( fail => 1 );

    is( $memcached->{store}{$key}, 3 );
    is( $memcached->{ttl}{$key},   60 );

=head1 DESCRIPTION

Mirrors the return values Koha::RateLimit::Counter relies on: incr is false when the key is
missing, decr stops at zero, and every method returns undef when the object was built with
fail so tests can prove the callers fail open.

=cut

=head2 new

    my $memcached = t::lib::Mocks::Memcached->new( fail => 0 );

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless { store => {}, ttl => {}, fail => $args{fail} }, $class;
}

=head2 incr

Increments an existing key, returns 0 when it does not exist.

=cut

sub incr {
    my ( $self, $key ) = @_;
    return if $self->{fail};
    return 0 unless exists $self->{store}{$key};
    return ++$self->{store}{$key};
}

=head2 add

Creates a key with a value and lifetime, returns 0 when it already exists.

=cut

sub add {
    my ( $self, $key, $value, $ttl ) = @_;
    return   if $self->{fail};
    return 0 if exists $self->{store}{$key};
    $self->{store}{$key} = $value;
    $self->{ttl}{$key}   = $ttl;
    return 1;
}

=head2 decr

Decrements a key without going below zero.

=cut

sub decr {
    my ( $self, $key ) = @_;
    return if $self->{fail};
    return 0 unless exists $self->{store}{$key};
    $self->{store}{$key}-- if $self->{store}{$key} > 0;
    return $self->{store}{$key} || '0E0';
}

1;
