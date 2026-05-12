#!/usr/bin/perl
use strict;
use warnings;
use Koha::Patrons;

my ( $userid, $cardnumber ) = @ARGV;

for my $args ( { userid => $userid }, { cardnumber => $cardnumber } ) {
    next unless $args->{userid} || $args->{cardnumber};
    my $p = Koha::Patrons->search($args)->next;
    if ($p) {
        my ( $k, $v ) = %$args;
        print "Deleting existing patron with $k=$v (borrowernumber=" . $p->borrowernumber . ")\n";
        $p->delete;
    }
}
