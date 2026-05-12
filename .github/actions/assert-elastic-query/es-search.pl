#!/usr/bin/perl
use strict;
use warnings;
use Koha::SearchEngine::Elasticsearch::QueryBuilder;
use Koha::SearchEngine::Elasticsearch::Search;

my $query        = shift @ARGV or die "usage: es-search.pl QUERY [TIMEOUT] [REQUIRE_HITS]\n";
my $timeout      = shift @ARGV // 30;
my $require_hits = shift @ARGV // 'true';

# Force the Elasticsearch backend regardless of the SearchEngine
# syspref — Koha::SearchEngine::QueryBuilder->new (the shim) returns
# Zebra's CCL builder when SearchEngine=Zebra, which then produces a
# string the ES search() method can't handle.
my $qb = Koha::SearchEngine::Elasticsearch::QueryBuilder->new( { index => 'biblios' } );
my $searcher = Koha::SearchEngine::Elasticsearch::Search->new( { index => 'biblios' } );

my $start = time;
my $last_hits;
my $last_err;

while ( time - $start < $timeout ) {
    my $hits_total;
    eval {
        my ( undef, $es_query ) = $qb->build_query_compat( undef, [$query] );
        my $results = $searcher->search( $es_query, undef, 1 );

        # ES 7+ returns total as an object; older returns int.
        my $total = $results->{hits}{total};
        $hits_total = ref $total eq 'HASH' ? $total->{value} : $total;
    };
    my $e = $@;
    if ($e) {
        $last_err = $e;
        warn "  t=" . ( time - $start ) . "s eval error: $e\n";
    }
    if ( defined $hits_total
        && ( !defined $last_hits || $hits_total != $last_hits ) )
    {
        printf "  t=%2ds hits=%d\n", time - $start, $hits_total;
        $last_hits = $hits_total;
    }
    if ( defined $hits_total && $hits_total >= 1 ) {
        print "Elasticsearch search for '$query' returned $hits_total hit(s)\n";
        exit 0;
    }
    sleep 2;
}

if ( $require_hits eq 'true' ) {
    die "Elasticsearch search for '$query' returned 0 hits after ${timeout}s "
        . ( $last_err ? "(last error: $last_err)" : "" ) . "\n";
}
print "Elasticsearch search for '$query' returned 0 hits "
    . "(require-hits=false, OK)\n";
