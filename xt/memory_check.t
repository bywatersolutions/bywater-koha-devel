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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Test::More tests => 2;
use FindBin;

my $pid = qx[ps ax | grep 'background_jobs_worker.pl --queue default' | grep -v grep | tail -n1 | awk '{print \$1}'];

chomp $pid;

SKIP: {
    skip "No background_jobs_worker.pl process running for the default queue", 1
      unless $pid;
    my $memory_usage = qx[pmap -x $pid | tail -n 1 | awk '/[0-9]/{print \$3}'];
    chomp $memory_usage;
    if ( $memory_usage > 150000 ) {
        fail("background_jobs_worker.pl is consuming more than 150Mo in memory: $memory_usage");
    }
    else {
        pass("background_jobs_worker.pl is consuming $memory_usage in memory");
    }
}

my $output = qx{$FindBin::Bin/../misc/background_jobs_worker.pl -m | grep 'Koha/Plugins.pm'};
is( $output, q{}, "Koha::Plugins not loaded by background_jobs_worker.pl" );
