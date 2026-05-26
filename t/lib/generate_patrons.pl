#!/usr/bin/env perl

# Generate 1.5M patrons for performance testing
# Inserts directly via DBI for speed, then triggers ES indexing in batches

use Modern::Perl;
use Getopt::Long;
use Time::HiRes qw(time);

use C4::Context;
use Koha::Database;

my $count      = 1_500_000;
my $batch_size = 5000;
my $index      = 0;
my $verbose    = 0;

GetOptions(
    'c|count=i' => \$count,
    'b|batch=i' => \$batch_size,
    'i|index'   => \$index,
    'v|verbose' => \$verbose,
) or die "Usage: $0 [-c count] [-b batch_size] [-i] [-v]\n";

my $dbh = C4::Context->dbh;
$dbh->{AutoCommit} = 0;

# Get valid branches and categories
my $branches = $dbh->selectcol_arrayref("SELECT branchcode FROM branches");
my $categories =
    $dbh->selectcol_arrayref("SELECT categorycode FROM categories WHERE category_type IN ('A','C','S','P')");

die "No branches found\n"   unless @$branches;
die "No categories found\n" unless @$categories;

my @firstnames = qw(James Mary Robert Patricia John Jennifer Michael Linda David Elizabeth
    William Barbara Richard Susan Joseph Jessica Thomas Sarah Charles Karen
    Christopher Lisa Daniel Nancy Matthew Betty Mark Sandra Donald Ashley
    Steven Emily Andrew Donna Paul Michelle Joshua Dorothy Kenneth Carol
    Kevin Amanda Brian Melissa George Deborah Edward Rebecca Timothy Sharon
    Ronald Laura Jason Cynthia Jeffrey Kathleen Ryan Amy Nicholas Shirley);

my @surnames = qw(Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez
    Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin
    Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson Walker
    Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson
    Baker Hall Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans Turner);

my @departments = qw(Engineering Marketing Sales Finance HR Legal Operations Research Support IT);
my @student_ids = map { sprintf( "STU%06d", $_ ) } 1 .. 100;

# Create searchable extended attribute types
print "Creating extended attribute types...\n" if $verbose;
$dbh->do(
    q{
    INSERT IGNORE INTO borrower_attribute_types (code, description, staff_searchable, searched_by_default, repeatable, unique_id)
    VALUES ('DEPT', 'Department', 1, 1, 0, 0),
           ('STUID', 'Student ID', 1, 1, 0, 1),
           ('CAMPUS', 'Campus', 1, 0, 0, 0),
           ('BARCODE', 'Alt barcode', 1, 0, 0, 1),
           ('ALLERGIES', 'Allergies', 0, 0, 0, 0),
           ('NOTES', 'Internal notes', 0, 0, 1, 0)
}
);
$dbh->commit;

my @campuses  = ( 'North', 'South',            'East',        'West',          'Main', 'Downtown', 'Online' );
my @allergies = ( 'None',  'Peanuts',          'Latex',       'Dust',          'Penicillin' );
my @notes     = ( 'VIP',   'Needs assistance', 'Do not call', 'Prefers email', 'Large print' );

my $sth = $dbh->prepare(
    q{
    INSERT INTO borrowers
        (surname, firstname, cardnumber, branchcode, categorycode, userid, dateenrolled, dateexpiry, email, phone, city, address)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
}
);

print "Generating $count patrons in batches of $batch_size...\n" if $verbose;

my $start    = time();
my $inserted = 0;

for my $i ( 1 .. $count ) {
    my $fn    = $firstnames[ int( rand(@firstnames) ) ];
    my $sn    = $surnames[ int( rand(@surnames) ) ];
    my $br    = $branches->[ int( rand(@$branches) ) ];
    my $cat   = $categories->[ int( rand(@$categories) ) ];
    my $card  = sprintf( "P%07d", $i );
    my $uid   = "patron$i";
    my $email = lc("${fn}.${sn}${i}\@example.com");
    my $phone = sprintf( "555-%03d-%04d", int( rand(999) ), int( rand(9999) ) );
    my $city  = (
        "Springfield", "Portland",  "Madison", "Franklin", "Clinton",
        "Georgetown",  "Arlington", "Salem",   "Bristol",  "Fairview"
    )[ int( rand(10) ) ];
    my $addr = int( rand(9999) ) . " " . (
        "Main",  "Oak",  "Elm",        "Park", "Cedar",
        "Maple", "Pine", "Washington", "Lake", "Hill"
    )[ int( rand(10) ) ] . " St";

    $sth->execute( $sn, $fn, $card, $br, $cat, $uid, '2024-01-01', '2027-12-31', $email, $phone, $city, $addr );
    $inserted++;

    if ( $inserted % $batch_size == 0 ) {
        $dbh->commit;
        my $elapsed = time() - $start;
        my $rate    = $inserted / $elapsed;
        printf "  %d / %d (%.1f%%) - %.0f patrons/sec\n", $inserted, $count, ( $inserted / $count * 100 ), $rate
            if $verbose;
    }
}

$dbh->commit;
my $elapsed = time() - $start;
printf "Inserted %d patrons in %.1f seconds (%.0f/sec)\n", $inserted, $elapsed, $inserted / $elapsed;

# Add extended attributes
print "Adding extended attributes...\n" if $verbose;
my $attr_sth = $dbh->prepare(
    q{
    INSERT INTO borrower_attributes (borrowernumber, code, attribute) VALUES (?, ?, ?)
}
);

my $patron_ids = $dbh->selectcol_arrayref("SELECT borrowernumber FROM borrowers WHERE cardnumber LIKE 'P%'");
my $attr_count = 0;
my $attr_start = time();

for my $pid (@$patron_ids) {

    # Every patron gets a department
    $attr_sth->execute( $pid, 'DEPT', $departments[ int( rand(@departments) ) ] );

    # 60% get a student ID
    if ( rand() < 0.6 ) {
        $attr_sth->execute( $pid, 'STUID', sprintf( "STU%07d", $pid ) );
    }

    # 40% get a campus
    if ( rand() < 0.4 ) {
        $attr_sth->execute( $pid, 'CAMPUS', $campuses[ int( rand(@campuses) ) ] );
    }

    # 50% get an alt barcode (searchable, not searched_by_default)
    if ( rand() < 0.5 ) {
        $attr_sth->execute( $pid, 'BARCODE', sprintf( "ALT%08d", $pid ) );
    }

    # 30% get allergies (non-searchable)
    if ( rand() < 0.3 ) {
        $attr_sth->execute( $pid, 'ALLERGIES', $allergies[ int( rand(@allergies) ) ] );
    }

    # 20% get notes (non-searchable, repeatable)
    if ( rand() < 0.2 ) {
        $attr_sth->execute( $pid, 'NOTES', $notes[ int( rand(@notes) ) ] );
    }
    $attr_count++;
    if ( $attr_count % $batch_size == 0 ) {
        $dbh->commit;
        printf "  Attributes: %d / %d (%.1f%%)\n", $attr_count, scalar(@$patron_ids),
            ( $attr_count / scalar(@$patron_ids) * 100 )
            if $verbose && $attr_count % ( $batch_size * 10 ) == 0;
    }
}
$dbh->commit;
my $attr_elapsed = time() - $attr_start;
printf "Added attributes for %d patrons in %.1f seconds (%.0f/sec)\n", $attr_count, $attr_elapsed,
    $attr_count / $attr_elapsed;

# Index if requested
if ($index) {
    print "Indexing patrons...\n";
    require Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();

    # Drop and recreate
    $indexer->drop_index() if $indexer->index_exists();
    $indexer->create_index();

    # Get all patron IDs
    my $ids   = $dbh->selectcol_arrayref("SELECT borrowernumber FROM borrowers WHERE anonymized = 0");
    my $total = scalar @$ids;
    print "Indexing $total patrons...\n";

    my $idx_start = time();
    my $idx_count = 0;
    while ( my @batch = splice( @$ids, 0, $batch_size ) ) {
        $indexer->index_patrons( \@batch );
        $idx_count += scalar @batch;
        if ( $verbose && $idx_count % ( $batch_size * 10 ) == 0 ) {
            my $idx_elapsed = time() - $idx_start;
            printf "  Indexed %d / %d (%.1f%%) - %.0f/sec\n",
                $idx_count, $total, ( $idx_count / $total * 100 ), $idx_count / $idx_elapsed;
        }
    }
    my $idx_elapsed = time() - $idx_start;
    printf "Indexed %d patrons in %.1f seconds (%.0f/sec)\n", $idx_count, $idx_elapsed, $idx_count / $idx_elapsed;
}

print "Done.\n";
