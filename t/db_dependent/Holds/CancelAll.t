#!/usr/bin/perl

use Modern::Perl;

use t::lib::Mocks;
use t::lib::TestBuilder;

use Test::More tests => 7;

use MARC::Record;

use C4::Context;
use C4::Biblio;
use C4::Items;
use C4::Members;
use Koha::Database;
use Koha::Holds;
use Koha::Account::Lines;

BEGIN {
    use FindBin;
    use lib $FindBin::Bin;
    use_ok('C4::Reserves');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new();
my $dbh     = C4::Context->dbh;

# Create two random branchcodees
my $category   = $builder->build( { source => 'Category' } );
my $branchcode = $builder->build( { source => 'Branch' } )->{branchcode};

my $borrowers_count = 2;

my ( $biblionumber, $title, $biblioitemnumber ) = create_helper_biblio('DUMMY');

C4::Context->set_preference( 'ExpireReservesMaxPickUpDelayCharge', '5.00' );

my ( undef, undef, $itemnumber ) = AddItem(
    {
        homebranchcode    => $branchcode,
        holdingbranchcode => $branchcode
    },
    $biblionumber
);

my $borrowernumber = AddMember(
    firstname    => 'my firstname',
    surname      => 'my surname ' . $_,
    categorycode => $category->{categorycode},
    branchcode   => $branchcode,
);

my $id = AddReserve(
    $branchcode,
    $borrowernumber,
    $biblionumber,
    my $bibitems = q{},
    my $priority = C4::Reserves::CalculatePriority($biblionumber),
    my $resdate,
    my $expdate,
    my $notes = q{},
    $title,
    my $checkitem = $itemnumber,
    my $found,
);

my $hold = Koha::Holds->find($id);
is( $hold->id, $id, 'Hold created correctly.' );

$dbh->do("DELETE FROM accountlines");

# Cancel with no cancelation fee
ModReserveCancelAll( $itemnumber, $borrowernumber );

$hold = Koha::Holds->find( $id );
is( $hold, undef, 'Hold canceled correctly' );

my $accountlines =
  Koha::Account::Lines->search( { borrowernumber => $borrowernumber } );
is( $accountlines->count(), 0, "No charge created for cancelation" );

$id = AddReserve(
    $branchcode,
    $borrowernumber,
    $biblionumber,
    $bibitems = q{},
    $priority = C4::Reserves::CalculatePriority($biblionumber),
    $resdate,
    $expdate,
    $notes = q{},
    $title,
    $checkitem = $itemnumber,
    $found,
);

# Cancel with cancelation fee
ModReserveCancelAll( $itemnumber, $borrowernumber, 1 );

$hold = Koha::Holds->find( $id );
is( $hold, undef, 'Hold canceled correctly' );

$accountlines =
  Koha::Account::Lines->search( { borrowernumber => $borrowernumber } );
is( $accountlines->count(), 1, "Found charge for cancelation" );
is( $accountlines->as_list->[0]->amountoutstanding, '5.000000', 'Charge is equal to ExpireReservesMaxPickUpDelayCharge' );

# Helper method to set up a Biblio.
sub create_helper_biblio {
    my $itemtype = shift;
    my $bib      = MARC::Record->new();
    my $title    = 'Silence in the library';
    $bib->append_fields(
        MARC::Field->new( '100', ' ', ' ', a => 'Moffat, Steven' ),
        MARC::Field->new( '245', ' ', ' ', a => $title ),
        MARC::Field->new( '942', ' ', ' ', c => $itemtype ),
    );
    return ( $biblionumber, $title, $biblioitemnumber ) = AddBiblio( $bib, '' );
}
