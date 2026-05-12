#!/usr/bin/perl
use strict;
use warnings;
use Koha::Patrons;
use Koha::Patron;
use Koha::Patron::Categories;
use Koha::Libraries;

my $cardnumber = $ARGV[0] // 'SIPTEST001';

my $cat = Koha::Patron::Categories->search( {}, { rows => 1 } )->next
    or die "no patron categories available; populate_db.pl must run first\n";
my $lib = Koha::Libraries->search( {}, { rows => 1 } )->next
    or die "no libraries available; populate_db.pl must run first\n";

my $existing = Koha::Patrons->search( { cardnumber => $cardnumber } )->next;
$existing->delete if $existing;

Koha::Patron->new(
    {   cardnumber   => $cardnumber,
        userid       => "sip_${cardnumber}",
        surname      => 'CITest',
        firstname    => 'Sip',
        branchcode   => $lib->branchcode,
        categorycode => $cat->categorycode,
    }
)->store;

print "Created SIP test patron cardnumber=$cardnumber\n";
