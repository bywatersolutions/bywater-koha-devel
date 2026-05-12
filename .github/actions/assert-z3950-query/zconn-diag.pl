#!/usr/bin/perl
use strict;
use warnings;
use C4::Context;

# Diagnostic that mirrors what Koha::Z3950Responder::ZebraSession does
# under the hood: open a Zconn for biblioserver and run a PQF search.
# If this works under koha-shell but yaz-client → z3950_responder
# returns "Cannot connect to upstream server", the problem is
# specific to the z3950 daemon's runtime (user, environment, fork
# state) rather than to the Zebra socket or the Koha config.

print "user/uid: $> ($<)\n";
print "KOHA_CONF=$ENV{KOHA_CONF}\n";
print "PERL5LIB=$ENV{PERL5LIB}\n";

eval {
    my $conn = C4::Context->Zconn( 'biblioserver', 0 );
    die "Zconn returned undef\n" unless $conn;
    print "Zconn obtained for biblioserver\n";

    my $results = $conn->search_pqf('@attr 1=4 a');
    my $size    = $results->size;
    print "search_pqf returned: $size hits\n";
    exit 0;
};
if ( my $e = $@ ) {
    if ( ref $e && $e->isa('ZOOM::Exception') ) {
        print "ZOOM::Exception caught:\n";
        print "  code:    " . $e->code . "\n";
        print "  message: " . $e->message . "\n";
        print "  diagset: " . $e->diagset . "\n";
        print "  addinfo: " . $e->addinfo . "\n";
    } else {
        print "Other exception: $e\n";
    }
    exit 1;
}
