#!/usr/bin/perl

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

use Test::More tests => 3;
use Test::NoWarnings;

use Koha::Status;

subtest 'new' => sub {
    plan tests => 1;

    my $status = Koha::Status->new();
    isa_ok( $status, 'Koha::Status', 'Constructor returns correct object type' );
};

subtest 'version' => sub {
    plan tests => 7;

    my $status       = Koha::Status->new();
    my $version_info = $status->version();

    is( ref($version_info), 'HASH', 'version() returns a hashref' );

    # Check required fields exist
    ok( exists $version_info->{version},     'version field exists' );
    ok( exists $version_info->{major},       'major field exists' );
    ok( exists $version_info->{minor},       'minor field exists' );
    ok( exists $version_info->{release},     'release field exists' );
    ok( exists $version_info->{maintenance}, 'maintenance field exists' );

    # Check version format and consistency
    like( $version_info->{version}, qr/^\d+\.\d+\.\d+\.\d+$/, 'version has correct format' );
};
