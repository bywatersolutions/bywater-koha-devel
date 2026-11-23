#!/usr/bin/perl

=head1 NAME

update_verified_crawler_ranges.pl - Rebuild the search engine crawler IP ranges the OPAC bot guard trusts

=head1 SYNOPSIS

    # Update the ranges shipped with Koha ( Koha/BotGuard/verified_crawlers.json )
    misc/maintenance/update_verified_crawler_ranges.pl

    # Write them somewhere else, then point crawler_ranges_file in koha-conf.xml at it
    misc/maintenance/update_verified_crawler_ranges.pl --output /var/lib/koha/verified_crawlers.json

=head1 DESCRIPTION

The OPAC bot guard ( Koha::Middleware::BotGuard ) lets a request whose user agent claims to be
one of the big search engine crawlers skip the challenge, but only when the client address is
inside the ranges that search engine publishes. This script downloads those ranges and writes
them to a JSON file.

It refuses to write a file when a source can't be fetched or has no ranges, since an empty list
would quietly start challenging that crawler.

=head1 OPTIONS

=over

=item B<-o|--output>

    The file to write. Defaults to the file shipped with Koha.

=item B<-h|--help>

    Print a brief help message.

=back

=cut

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
use Getopt::Long qw( GetOptions );
use JSON;
use LWP::UserAgent;
use Net::Netmask;
use POSIX      qw( strftime );
use Pod::Usage qw( pod2usage );

use Koha::Middleware::BotGuard;
use Koha::Script;

my %sources = (
    googlebot   => 'https://developers.google.com/static/crawling/ipranges/common-crawlers.json',
    bingbot     => 'https://www.bing.com/toolbox/bingbot.json',
    applebot    => 'https://search.developer.apple.com/applebot.json',
    duckduckbot => 'https://duckduckgo.com/duckduckbot.json',
);

my $output = $Koha::Middleware::BotGuard::DEFAULT_CRAWLER_RANGES_FILE;
my $help;
GetOptions(
    'o|output=s' => \$output,
    'h|help'     => \$help,
) or pod2usage(2);
pod2usage(1) if $help;

my $ua = LWP::UserAgent->new( timeout => 30, agent => 'Koha update_verified_crawler_ranges.pl' );

my %ranges;
foreach my $crawler ( sort keys %sources ) {
    my $response = $ua->get( $sources{$crawler} );
    die sprintf( "Could not fetch %s: %s\n", $sources{$crawler}, $response->status_line )
        unless $response->is_success;

    my $prefixes = eval { decode_json( $response->decoded_content )->{prefixes} };
    my @valid    = sort grep { Net::Netmask->new2($_) }
        map { $_->{ipv4Prefix} // $_->{ipv6Prefix} // () } @{ ref $prefixes eq 'ARRAY' ? $prefixes : [] };

    die "No ranges found for $crawler in $sources{$crawler}, leaving $output unchanged\n" unless @valid;

    $ranges{$crawler} = \@valid;
    say sprintf( '%s: %d ranges', $crawler, scalar @valid );
}

open my $fh, '>', $output or die "Could not write $output: $!\n";
print $fh JSON->new->pretty->canonical->encode(
    {
        updated => strftime( '%Y-%m-%d', localtime ),
        sources => \%sources,
        ranges  => \%ranges,
    }
);
close $fh;
say "Wrote $output";
