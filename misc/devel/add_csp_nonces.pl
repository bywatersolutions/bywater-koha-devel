#!/usr/bin/env perl

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

=head1 NAME

add_csp_nonces.pl - Add CSP nonces to inline script tags in templates

=head1 SYNOPSIS

    # Dry run (default) - show what would be changed
    perl misc/devel/add_csp_nonces.pl

    # Actually modify files
    perl misc/devel/add_csp_nonces.pl --apply

    # Verbose output
    perl misc/devel/add_csp_nonces.pl --verbose

    # Process specific directory
    perl misc/devel/add_csp_nonces.pl --dir koha-tmpl/opac-tmpl

=head1 DESCRIPTION

This script adds CSP (Content Security Policy) nonce attributes to inline
<script> tags in Koha templates. This is required for CSP compliance.

The script:
- Finds all .tt and .inc files in koha-tmpl/
- Identifies inline <script> tags (those without src= attribute)
- Adds nonce="[% Koha.CSPNonce | $raw %]" attribute
- Skips tags that already have nonce attributes
- Skips external scripts (those with src= attribute)

=cut

use Modern::Perl;
use Carp qw( carp );
use Getopt::Long;
use Pod::Usage;

use Koha::Devel::Files;

my $apply   = 0;
my $verbose = 0;
my $help    = 0;
my $dir     = 'koha-tmpl';

GetOptions(
    'apply'     => \$apply,
    'verbose|v' => \$verbose,
    'help|h'    => \$help,
    'dir=s'     => \$dir,
) or pod2usage(2);

pod2usage(1) if $help;

# The nonce attribute to add
my $nonce_attr = 'nonce="[% Koha.CSPNonce | $raw %]"';

my %stats = (
    files_scanned  => 0,
    files_modified => 0,
    tags_modified  => 0,
);

sub process_file {
    my ($file) = @_;

    $stats{files_scanned}++;

    open my $fh, '<:encoding(UTF-8)', $file or do {
        carp "Cannot read $file: $!";
        return;
    };
    my $content = do { local $/; <$fh> };
    close $fh;

    my $original = $content;
    my $modified = 0;

    # Match <script tags that:
    # - Don't have src= attribute (inline scripts)
    # - Don't already have nonce= attribute
    #
    # We use a callback replacement to handle each match individually
    $content =~ s{
        (<script|<style)                    # Capture opening <script or <style
        (                            # Capture existing attributes
            (?:
                \s+                  # Whitespace before attribute
                (?!src\s*=)          # Not followed by src=
                (?!nonce\s*=)        # Not followed by nonce=
                [a-zA-Z][\w-]*       # Attribute name
                (?:                  # Optional attribute value
                    \s*=\s*
                    (?:
                        "[^"]*"      # Double-quoted value
                        |'[^']*'     # Single-quoted value
                        |[^\s>]+     # Unquoted value
                    )
                )?
            )*
        )
        (\s*)                        # Whitespace before >
        (>)                          # Closing >
    }{
        my ($open, $attrs, $ws, $close) = ($1, $2, $3, $4);

        # Check if this tag has src= (external script - skip)
        if ($attrs =~ /\bsrc\s*=/i) {
            "$open$attrs$ws$close";  # Return unchanged
        }
        # Check if already has nonce= (skip)
        elsif ($attrs =~ /\bnonce\s*=/i) {
            "$open$attrs$ws$close";  # Return unchanged
        }
        else {
            $modified++;
            "$open $nonce_attr$attrs$ws$close";
        }
    }xsge;

    if ($modified) {
        $stats{files_modified}++;
        $stats{tags_modified} += $modified;

        if ( $verbose || !$apply ) {
            say "File: $file ($modified tag" . ( $modified > 1 ? 's' : '' ) . ")";
        }

        if ($apply) {
            open my $out, '>:encoding(UTF-8)', $file or do {
                carp "Cannot write $file: $!";
                return;
            };
            print $out $content;
            close $out;
            say "  Modified" if $verbose;
        }
    }
}

# Find and process all template files
my $dev_files = Koha::Devel::Files->new( { context => 'nonce' } );
my @tt_files  = $dev_files->ls_tt_files();
for my $file (@tt_files) {
    process_file($file);
}

# Print summary
say "";
say "=" x 60;
say "Summary:";
say "  Files scanned:  $stats{files_scanned}";
say "  Files modified: $stats{files_modified}";
say "  Tags modified:  $stats{tags_modified}";
say "=" x 60;

if ( !$apply && $stats{tags_modified} > 0 ) {
    say "";
    say "This was a dry run. Use --apply to actually modify files.";
}

exit( $stats{tags_modified} > 0 ? 0 : 1 );
