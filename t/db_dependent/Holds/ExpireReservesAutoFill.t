#!/usr/bin/perl

use Modern::Perl;

use Test::More tests => 9;

use t::lib::Mocks;
use t::lib::TestBuilder;

use MARC::Record;

use C4::Context;
use C4::Biblio;
use C4::Items;
use Koha::Database;
use Koha::Holds;

BEGIN {
    use FindBin;
    use lib $FindBin::Bin;
    use_ok('C4::Reserves');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new();
my $dbh     = C4::Context->dbh;

# Create two random branches
my $library = $builder->build( { source => 'Branch' } );
my $branchcode = $library->{branchcode};

$dbh->do('DELETE FROM reserves');
$dbh->do('DELETE FROM message_queue');

# Create a biblio instance for testing
my ($biblionumber) = create_helper_biblio('DUMMY');

# Create item instance for testing.
my ( $item_bibnum, $item_bibitemnum, $itemnumber ) =
  AddItem( { homebranch => $branchcode, holdingbranch => $branchcode },
    $biblionumber );

my $patron_1 = $builder->build( { source => 'Borrower' } );
my $patron_2 = $builder->build( { source => 'Borrower' } );
my $patron_3 = $builder->build( { source => 'Borrower' } );

# Add a hold on the item for each of our patrons
my $hold_1 = Koha::Hold->new(
    {
        priority       => 0,
        borrowernumber => $patron_1->{borrowernumber},
        branchcode     => $library->{branchcode},
        biblionumber   => $biblionumber,
        itemnumber     => $itemnumber,
        found          => 'W',
        reservedate    => '1900-01-01',
        waitingdate    => '1900-01-01',
        expirationdate => '1900-01-01',
        lowestPriority => 0,
        suspend        => 0,
    }
)->store();
my $hold_2 = Koha::Hold->new(
    {
        priority       => 1,
        borrowernumber => $patron_2->{borrowernumber},
        branchcode     => $library->{branchcode},
        biblionumber   => $biblionumber,
        itemnumber     => $itemnumber,
        reservedate    => '1900-01-01',
        expirationdate => '9999-01-01',
        lowestPriority => 0,
        suspend        => 0,
    }
)->store();
my $hold_3 = Koha::Hold->new(
    {
        priority       => 2,
        borrowernumber => $patron_2->{borrowernumber},
        branchcode     => $library->{branchcode},
        biblionumber   => $biblionumber,
        itemnumber     => $itemnumber,
        reservedate    => '1900-01-01',
        expirationdate => '9999-01-01',
        lowestPriority => 0,
        suspend        => 0,
    }
)->store();

# Test CancelExpiredReserves
t::lib::Mocks::mock_preference( 'ExpireReservesMaxPickUpDelay', 1 );
t::lib::Mocks::mock_preference( 'ReservesMaxPickUpDelay',       1 );
t::lib::Mocks::mock_preference( 'ExpireReservesOnHolidays',     1 );
t::lib::Mocks::mock_preference( 'ExpireReservesAutoFill',       1 );
t::lib::Mocks::mock_preference( 'ExpireReservesAutoFillEmail',
    'kyle@example.com' );

CancelExpiredReserves();

my @holds = Koha::Holds->search( {}, { order_by => 'priority' } );
$hold_2 = $holds[0];
$hold_3 = $holds[1];

is( @holds,            2,   'Found 2 holds' );
is( $hold_2->priority, 0,   'Next hold in line now has priority of 0' );
is( $hold_2->found,    'W', 'Next hold in line is now set to waiting' );

my @messages = $schema->resultset('MessageQueue')
  ->search( { letter_code => 'HOLD_CHANGED' } );
is( @messages, 1, 'Found 1 message in the message queue' );
is( $messages[0]->to_address, 'kyle@example.com', 'Message sent to correct email address' );

$hold_2->expirationdate('1900-01-01')->store();

CancelExpiredReserves();

@holds = Koha::Holds->search( {}, { order_by => 'priority' } );
$hold_3 = $holds[0];

is( @holds,            1,   'Found 1 hold' );
is( $hold_3->priority, 0,   'Next hold in line now has priority of 0' );
is( $hold_3->found,    'W', 'Next hold in line is now set to waiting' );

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
    return my ( $b, $t, $bi ) = AddBiblio( $bib, '' );
}
