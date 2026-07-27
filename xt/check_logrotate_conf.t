#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More;
use Test::NoWarnings;

use File::Temp qw( tempdir );

my @logrotate_files = glob 'debian/*.logrotate';

plan tests => scalar(@logrotate_files) + 2;

ok( scalar @logrotate_files, 'Found logrotate configuration files in debian/' );

my $tempdir = tempdir( CLEANUP => 1 );

foreach my $file (@logrotate_files) {
    subtest "$file is a valid logrotate configuration" => sub {
        plan tests => 3;

        # Debug mode parses the configuration and simulates rotation without touching any files
        my $state_file = "$tempdir/state";
        my $output     = `logrotate --debug --state '$state_file' '$file' 2>&1`;
        my $exit_code  = $? >> 8;

        is( $exit_code, 0, "logrotate exits with 0 for $file" );

        my @error_lines = grep { /^error/ } split /\n/, $output;
        is( join( "\n", @error_lines ), q{}, "logrotate reports no errors for $file" );

        # logrotate treats unknown directives as warnings and still exits zero,
        # so fail on any warning other than the debug mode banner
        my @warning_lines = grep { /^warning/ && !/debug mode/ } split /\n/, $output;
        is( join( "\n", @warning_lines ), q{}, "logrotate reports no warnings for $file" );
    };
}
