#!/usr/bin/perl

# Copyright 2026 Koha development team
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
use Test::More tests => 3;
use Test::NoWarnings;
use File::Slurp;
use Data::Dumper;

use Koha::Devel::Files;

my $dev_files = Koha::Devel::Files->new;
my @files     = $dev_files->ls_tt_files;
ok( @files > 0, 'We should test something' );

my @errors;
for my $file (@files) {
    my @e = catch_missing_nonce($file);
    push @errors, sprintf "%s:%s", $file, join( ",", @e ) if @e;
}

is(
    @errors, 0,
    "Not all <script> or <style> tags in the following files have 'nonce' attribute (see bug 38365)"
) or diag( Dumper @errors );

sub catch_missing_nonce {
    my ($file) = @_;

    my @lines = read_file($file);
    my @errors;
    return unless grep { $_ =~ m[<(script|style)] } @lines;
    my $line_number = 0;
    for my $line (@lines) {
        $line_number++;
        if ( $line =~ m{<script} && $line !~ m{<script nonce=} && $line !~ m{src="} ) {
            next if $line =~ m{Babeltheque_url_js};    # Exception
            push @errors, "$line_number: $line";
        }
        if ( $line =~ m{<style} && $line !~ m{<style nonce=} ) {
            push @errors, "$line_number: $line";
        }

    }
    return @errors;
}
