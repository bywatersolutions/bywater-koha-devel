#!/bin/perl

use C4::Context;
use Koha::Patrons;
use C4::Utils::DataTables::Patrons::ElasticSearch;

my $patrons = Koha::Patrons->search();

while ( my $p = $patrons->next ) {

    my $result = C4::Utils::DataTables::Patrons::ElasticSearch::index( $p );

    warn Data::Dumper::Dumper($result);
}
