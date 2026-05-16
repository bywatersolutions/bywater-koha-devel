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
    'c|count=i'  => \$count,
    'b|batch=i'  => \$batch_size,
    'i|index'    => \$index,
    'v|verbose'  => \$verbose,
) or die "Usage: $0 [-c count] [-b batch_size] [-i] [-v]\n";

my $dbh = C4::Context->dbh;
$dbh->{AutoCommit} = 0;

# Get valid branches and categories
my $branches   = $dbh->selectcol_arrayref("SELECT branchcode FROM branches");
my $categories = $dbh->selectcol_arrayref("SELECT categorycode FROM categories WHERE category_type IN ('A','C','S','P')");

die "No branches found\n" unless @$branches;
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

my $sth = $dbh->prepare(q{
    INSERT INTO borrowers
        (surname, firstname, cardnumber, branchcode, categorycode, userid, dateenrolled, dateexpiry, email, phone, city, address)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
});

print "Generating $count patrons in batches of $batch_size...\n" if $verbose;

my $start = time();
my $inserted = 0;

for my $i (1 .. $count) {
    my $fn   = $firstnames[ int(rand(@firstnames)) ];
    my $sn   = $surnames[ int(rand(@surnames)) ];
    my $br   = $branches->[ int(rand(@$branches)) ];
    my $cat  = $categories->[ int(rand(@$categories)) ];
    my $card = sprintf("P%07d", $i);
    my $uid  = "patron$i";
    my $email = lc("${fn}.${sn}${i}\@example.com");
    my $phone = sprintf("555-%03d-%04d", int(rand(999)), int(rand(9999)));
    my $city  = ("Springfield", "Portland", "Madison", "Franklin", "Clinton",
                 "Georgetown", "Arlington", "Salem", "Bristol", "Fairview")[int(rand(10))];
    my $addr  = int(rand(9999)) . " " . ("Main", "Oak", "Elm", "Park", "Cedar",
                 "Maple", "Pine", "Washington", "Lake", "Hill")[int(rand(10))] . " St";

    $sth->execute($sn, $fn, $card, $br, $cat, $uid, '2024-01-01', '2027-12-31', $email, $phone, $city, $addr);
    $inserted++;

    if ($inserted % $batch_size == 0) {
        $dbh->commit;
        my $elapsed = time() - $start;
        my $rate = $inserted / $elapsed;
        printf "  %d / %d (%.1f%%) - %.0f patrons/sec\n", $inserted, $count, ($inserted/$count*100), $rate
            if $verbose;
    }
}

$dbh->commit;
my $elapsed = time() - $start;
printf "Inserted %d patrons in %.1f seconds (%.0f/sec)\n", $inserted, $elapsed, $inserted/$elapsed;

# Index if requested
if ($index) {
    print "Indexing patrons...\n";
    require Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();

    # Drop and recreate
    $indexer->drop_index() if $indexer->index_exists();
    $indexer->create_index();

    # Get all patron IDs
    my $ids = $dbh->selectcol_arrayref("SELECT borrowernumber FROM borrowers WHERE anonymized = 0");
    my $total = scalar @$ids;
    print "Indexing $total patrons...\n";

    my $idx_start = time();
    my $idx_count = 0;
    while (my @batch = splice(@$ids, 0, $batch_size)) {
        $indexer->index_patrons(\@batch);
        $idx_count += scalar @batch;
        if ($verbose && $idx_count % ($batch_size * 10) == 0) {
            my $idx_elapsed = time() - $idx_start;
            printf "  Indexed %d / %d (%.1f%%) - %.0f/sec\n",
                $idx_count, $total, ($idx_count/$total*100), $idx_count/$idx_elapsed;
        }
    }
    my $idx_elapsed = time() - $idx_start;
    printf "Indexed %d patrons in %.1f seconds (%.0f/sec)\n", $idx_count, $idx_elapsed, $idx_count/$idx_elapsed;
}

print "Done.\n";
