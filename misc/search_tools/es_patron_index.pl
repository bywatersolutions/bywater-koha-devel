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
[B<-w|--where>=C<SQL>]
[B<-v|--verbose>]
[B<-h|--help>]

=head1 DESCRIPTION

Creates, rebuilds, or updates the Elasticsearch patrons index.

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

=item B<-w|--where>=C<SQL>

Additional SQL WHERE clause to limit patrons indexed.
Example: --where "branchcode = 'CPL'"

=item B<-v|--verbose>

Increase verbosity. Repeat for more detail.

=item B<-h|--help>

Show help.

=back

=cut

use Modern::Perl;
use autodie;
use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );
use Try::Tiny    qw( catch try );

use Koha::Script;
use C4::Context;
use Koha::Patrons;
use Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

my $verbose = 0;
my $commit  = 1000;
my ( $delete, $reset, $help );
my ( @ids, $where );

$| = 1;

GetOptions(
    'c|commit=i' => \$commit,
    'd|delete'   => \$delete,
    'r|reset'    => \$reset,
    'id=i'       => \@ids,
    'w|where=s'  => \$where,
    'v|verbose+' => \$verbose,
    'h|help'     => \$help,
) or pod2usage(2);

pod2usage(1) if $help;

$delete = 1 if $reset;

my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();

# Handle index creation/reset
if ($delete) {
    print "Dropping patrons index...\n" if $verbose;
    $indexer->drop_index() if $indexer->index_exists();
    print "Creating patrons index...\n" if $verbose;
    $indexer->create_index();
    print "Index created.\n" if $verbose;
}

# Ensure index exists
unless ( $indexer->index_exists() ) {
    print "Index does not exist. Creating...\n";
    $indexer->create_index();
}

# Determine which patrons to index
my $query = { anonymized => 0 };
if (@ids) {
    $query->{borrowernumber} = { -in => \@ids };
} elsif ($where) {
    # Raw SQL where clause via literal
    $query = \[ "anonymized = 0 AND $where" ];
}

my $patrons_rs = Koha::Patrons->search($query);
my $total      = $patrons_rs->count;

print "Indexing $total patrons (batch size: $commit)...\n" if $verbose;

my $count    = 0;
my @batch;

while ( my $patron = $patrons_rs->next ) {
    push @batch, $patron->borrowernumber;

    if ( scalar @batch >= $commit ) {
        _index_batch( $indexer, \@batch );
        $count += scalar @batch;
        printf "  %d / %d (%.1f%%)\n", $count, $total, ( $count / $total * 100 ) if $verbose;
        @batch = ();
    }
}

# Final batch
if (@batch) {
    _index_batch( $indexer, \@batch );
    $count += scalar @batch;
}

print "Done. Indexed $count patrons.\n" if $verbose;
$indexer->set_index_status_ok();

sub _index_batch {
    my ( $indexer, $ids ) = @_;
    try {
        $indexer->index_patrons($ids);
    } catch {
        warn "Error indexing batch: $_\n";
    };
}
