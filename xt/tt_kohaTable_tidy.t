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
use File::Slurp qw( read_file );
use Test::More;

use Test::NoWarnings;

use Koha::Devel::Files;

my $dev_files = Koha::Devel::Files->new( { context => 'tidy' } );
my @tt_files  = $dev_files->ls_tt_files;

plan tests => scalar(@tt_files) + 1;

for my $file (@tt_files) {

    my @lines = read_file($file);
    my $fails = 0;
    my ( $in_script, $has_tt_tags, $has_kohaTable );
    for my $line (@lines) {

        if ( $line =~ m{<script} ) {
            $in_script = 1;
            next;
        }

        if ( $line =~ m{<\/script>} ) {
            if ( $has_kohaTable && $has_tt_tags ) {
                $fails++;
            }
            $has_kohaTable = 0;
            $has_tt_tags   = 0;
            $in_script     = 0;
        }
        next unless $in_script;

        $has_kohaTable ||= $line =~ m{\).kohaTable\(};

        $has_tt_tags ||= $line =~ m{\[\%.*?\%\]}s;
    }

    is( $fails, 0, "$file has 'kohaTable' instances in a <script> tag with Template::Toolkit tags." );
}
