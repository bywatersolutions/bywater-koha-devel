#!/usr/bin/perl

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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use WebService::ILS::OverDrive::Library;
use Getopt::Long;
use Pod::Usage;
use JSON;

my $help;
my $man;
my $verbose;
my $full;

GetOptions(
    'h'   => \$help,
    'man' => \$man,
    'v'   => \$verbose,
    'f'   => \$full,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -verbose => 2 ) if $man;

use Koha::SearchEngine;
use Koha::SearchEngine::ElasticSearch::Indexer;
use C4::Context;

use Data::Dumper;


# We should put this in config eventually, but it is dependent on the Overdrive API
#
my $fixes = ['copy_field(id,Local-number)','move_field(_id,es_id)'];


# create an indexer object
my $indexer = Koha::SearchEngine::ElasticSearch::Indexer->new(
    { index => $Koha::SearchEngine::BIBLIOS_INDEX } );

unless ( $indexer->store ) {
    my $params = $indexer->get_elasticsearch_params();
    $indexer->store(
        Catmandu::Store::ElasticSearch->new(
            %$params,
            index_settings => $indexer->get_elasticsearch_settings(),
            index_mappings => $indexer->get_elasticsearch_mappings(),
        )
    );
}

my $client_id     = C4::Context->preference('OverDriveClientKey');
my $client_secret = C4::Context->preference('OverDriveClientSecret');
my $library_id    = C4::Context->preference('OverDriveLibraryID');
my $od_client = WebService::ILS::OverDrive::Library->new(
    {
        test          => 1,
        client_id     => $client_id,
        client_secret => $client_secret,
        library_id    => $library_id
    }
);

my $results;
my %search_params;


unless ($full) {
    $search_params{'lastTitleUpdateTime='} = '';
}

$search_params{'limit'} = 20;

$results = $od_client->native_search( \%search_params );

# set up our importer to import in the JSON files
# Overdrive paginates, so we need to deal with that

# import and index the first page of results
my $json = to_json($results->{products} );
my $importer =
  Catmandu->importer( 'JSON', file => \$json, fix => $fixes );
   $importer->each(sub {
              my $item = shift;
              my $stored = $indexer->store->bag->add($item);
              $indexer->store->bag->commit;
                          });

if ( $results->{pages} ){
    foreach ( 2 .. $results->{pages} ) {

        # deal with any more results
        $search_params{page} = $_;
        my $next_results = $od_client->native_search( \%search_params );
        $importer =
          Catmandu->importer( 'JSON', file => $next_results->{items}, fix => $fixes );
        $indexer->store->bag->add_many($importer);
        $indexer->store->bag->commit;
    }
}
=head1 NAME

overdrive_get_collection.pl - Fetches an indexes a libraries collection from overdrive

=head1 SYNOPSIS

overdrive_get_collection.pl
  [ -f ]

 Options:
   -h               brief help message
   --m              full documentation
   -v               verbose
   -f               full reindex

=head1 OPTIONS

=over 8

=item B<-h>

Prints a brief help message and exits

=item B<--man>

Prints the manual page and exits

=item B<-v>

Verbose, without this only fatal errors are reported

=item B<-f>

Full, fetches all records and reindexes

=back

=head1 DESCRIPTION

This script is designed to grab overdrive collections and create MARC records
and store them

=head1 USAGE EXAMPLES

C<overdrive_get_collection.pl> - In this most basic usage, with no command arguments
we get the udpdated records since last time we checked, and index them

C<overdrive_get_collection.pl -f -v> - Gets the entire collection and indexes it, being
verbose in the process

=cut
