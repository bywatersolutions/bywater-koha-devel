#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

es_patron_index.pl - Manage the Elasticsearch patrons index

=head1 SYNOPSIS

B<es_patron_index.pl>
[B<-c|--commit>=C<count>]
[B<-d|--delete>]
[B<-r|--reset>]
[B<--id>=C<borrowernumber>]
[B<-p|--processes>=C<count>]
[B<-v|--verbose>]
[B<-h|--help>]

=head1 OPTIONS

=over

=item B<-c|--commit>=C<count>

Batch size for bulk indexing. Default: 1000.

=item B<-d|--delete>

Drop and recreate the index before indexing.

=item B<-r|--reset>

Reset mappings (implies --delete).

=item B<--id>=C<borrowernumber>

Index only the specified patron(s). May be repeated.

=item B<-p|--processes>=C<count>

Number of parallel processes for indexing. Default: 1.

=item B<-v|--verbose>

Increase verbosity.

=item B<-h|--help>

Show help.

=back

=cut

use Modern::Perl;
use autodie;
use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );
use Try::Tiny    qw( catch try );
use POSIX        qw( ceil );

use Koha::Script;
use C4::Context;
use Koha::Patrons;
use Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

my $verbose   = 0;
my $commit    = 1000;
my $processes = 1;
my ( $delete, $reset, $help );
my @ids;

$| = 1;

GetOptions(
    'c|commit=i'    => \$commit,
    'd|delete'      => \$delete,
    'r|reset'       => \$reset,
    'id=i'          => \@ids,
    'p|processes=i' => \$processes,
    'v|verbose+'    => \$verbose,
    'h|help'        => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

die "Argument -p|--processes cannot be combined with --id\n"
    if $processes > 1 && @ids;

$delete = 1 if $reset;

my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();

# Handle index creation/reset (only in main process)
if ($delete) {
    print "Dropping patrons index...\n" if $verbose;
    $indexer->drop_index()              if $indexer->index_exists();
    print "Creating patrons index...\n" if $verbose;
    $indexer->create_index();
    print "Index created.\n" if $verbose;
}

unless ( $indexer->index_exists() ) {
    print "Index does not exist. Creating...\n";
    $indexer->create_index();
}

# Determine which patrons to index
my $total;
if (@ids) {
    $total = scalar @ids;
} else {
    $total = Koha::Patrons->search( { anonymized => 0 } )->count;
}

print "Indexing $total patrons (batch size: $commit, processes: $processes)...\n" if $verbose;

# Fork child processes for parallel indexing
my $slice_index = 0;
my $slice_count = $processes;

if ( $slice_count > 1 ) {
    for ( my $proc = 1 ; $proc < $slice_count ; $proc++ ) {
        my $pid = fork();
        die "Failed to fork\n" unless defined $pid;
        if ( $pid == 0 ) {
            $slice_index = $proc;
            last;
        }
    }

    # Stagger commits slightly to avoid ES bulk contention
    $commit = int( $commit * ( 1 + 0.10 * $slice_index ) );
}

# Each process gets its slice
my $patrons_rs;
if (@ids) {
    $patrons_rs = Koha::Patrons->search( { borrowernumber => { -in => \@ids } } );
} else {
    my $dbh       = C4::Context->dbh;
    my $slice_ids = $dbh->selectcol_arrayref(
        "SELECT borrowernumber FROM borrowers WHERE anonymized = 0 AND MOD(borrowernumber, ?) = ? ORDER BY borrowernumber",
        undef, $slice_count, $slice_index
    );
    $patrons_rs = Koha::Patrons->search( { borrowernumber => { -in => $slice_ids } } );
}

my $slice_total = $patrons_rs->count;
my $count       = 0;
my @batch;

# Re-create indexer in child (fresh ES connection)
$indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new() if $slice_index > 0;

while ( my $patron = $patrons_rs->next ) {
    push @batch, $patron->borrowernumber;

    if ( scalar @batch >= $commit ) {
        _index_batch( $indexer, \@batch );
        $count += scalar @batch;
        printf "  [%d/%d] %d / %d (%.1f%%)\n", $slice_index + 1, $slice_count, $count, $slice_total,
            ( $count / $slice_total * 100 )
            if $verbose;
        @batch = ();
    }
}

if (@batch) {
    _index_batch( $indexer, \@batch );
    $count += scalar @batch;
}

if ( $slice_count > 1 && $slice_index > 0 ) {

    # Child process: exit
    printf "  [%d/%d] Done. Indexed %d patrons.\n", $slice_index + 1, $slice_count, $count if $verbose;
    exit 0;
}

# Parent: wait for children
if ( $slice_count > 1 ) {
    for ( my $proc = 1 ; $proc < $slice_count ; $proc++ ) {
        wait();
    }
}

print "Done. Indexed $total patrons.\n" if $verbose;
$indexer->set_index_status_ok();

sub _index_batch {
    my ( $indexer, $ids ) = @_;
    try {
        $indexer->index_patrons($ids);
    } catch {
        warn "Error indexing batch: $_\n";
    };
}
