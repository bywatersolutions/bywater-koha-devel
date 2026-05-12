#!/usr/bin/perl
use strict;
use warnings;
use C4::Biblio qw(AddBiblio);
use C4::Search;
use MARC::Record;
use MARC::Field;

my $unique  = $ARGV[0] || "SystemdCITestIdx_$$" . time();
my $timeout = $ARGV[1] || 180;

my $marc = MARC::Record->new;
$marc->leader('00000nam a2200000   4500');
$marc->append_fields(
    MARC::Field->new( '100', '1', ' ', 'a' => 'CI Test Author' ),
    MARC::Field->new( '245', '0', '0', 'a' => $unique ),
);

my ($biblionumber) = AddBiblio( $marc, '' );
die "AddBiblio returned no biblionumber\n" unless $biblionumber;
print "Added biblio $biblionumber with title='$unique'\n";

print "Polling Zebra via SimpleSearch (timeout ${timeout}s)...\n";

my $start = time;
my $last_hits;
while ( time - $start < $timeout ) {
    my ( $err, undef, $hits )
        = C4::Search::SimpleSearch( qq{"$unique"}, 0, 1 );
    if ( $err && $err ne '<none>' ) {
        warn "  t=" . ( time - $start ) . "s search error: $err\n";
    }
    if ( defined $hits && ( !defined $last_hits || $hits != $last_hits ) ) {
        printf "  t=%2ds hits=%d\n", time - $start, $hits;
        $last_hits = $hits;
    }
    if ( defined $hits && $hits >= 1 ) {
        print "✓ koha-indexer drained zebraqueue — biblio $biblionumber "
            . "is searchable in Zebra after "
            . ( time - $start )
            . "s\n";
        exit 0;
    }
    sleep 5;
}

die "Zebra indexer did not pick up biblio $biblionumber within ${timeout}s "
    . "(SimpleSearch never returned a hit for '$unique'). "
    . "koha-indexer daemon may be stuck or not consuming zebraqueue.\n";
