#!/usr/local/bin/perl

##
## This script checks one global resource against all the other
## resources that a site has active and tries to determine what
## extra journals and coverage the new one will provide.
##

$| = 1;

use lib qw(lib);

use CUFTS::Config;
use CUFTS::Util::Simple;

use Getopt::Long;
use String::Util qw(hascontent trim);
use Log::Log4perl qw(:easy);

use strict;

Log::Log4perl->easy_init($INFO);
my $logger = Log::Log4perl->get_logger();

my $schema = CUFTS::Config::get_schema();

my %options;
GetOptions( \%options, 'site_key=s', 'site_id=i', 'resource_id=i' );

$logger->info('Starting resource comparison script.');

my $site;
if ( defined $options{site_id} ) {
    $site = $schema->resultset('Sites')->find({ id =>  $options{site_id} });
}
elsif ( defined $options{site_key} ) {
    $site = $schema->resultset('Sites')->find({ key =>  $options{site_key} });
}
else {
    usage();
    exit;
}
if ( !defined $site ) {
    $logger->error('Unable to load site.');
    exit;
}
$logger->info('Loaded site: ' . $site->name);

my $check_resource;
if ( defined $options{resource_id} ) {
    $check_resource = $schema->resultset('GlobalResources')->find({ id =>  $options{resource_id} });
}
else {
    usage();
    exit;
}
if ( !defined $check_resource ) {
    $logger->error('Unable to load resource.');
    exit;
}
$logger->info('Loaded resource: ' . $check_resource->name);

if ( !$check_resource->do_module('can', 'compare_against_existing') ) {
    $logger->error('Module does not implement compare_against_existing().');
    exit();
}
my $result = $check_resource->do_module('compare_against_existing', $schema, $check_resource, $site, $logger );

print 'Checking ' . $check_resource->name . ' against all holdings for ' . $site->name . "\n";

print "\nUnique records\n\n";
foreach my $record ( @{$result->{unique_printable}} ) {
    print join("\t", @$record), "\n";
}

print "\nRecords with current coverage where existing records do not have current coverage\n\n";
foreach my $record ( @{$result->{more_current_printable}} ) {
    print join("\t", @$record), "\n";
}

print "\nRecords which don't add more current coverage\n\n";
foreach my $record ( @{$result->{others_printable}} ) {
    print join("\t", @$record), "\n";
}
print "\n";

sub usage {
    print <<EOF;

compare_new_resource - hecks one global resource against all the other resources that a site has active and tries to determine what extra journals and coverage the new one will provide.

 site_key=XXX    - CUFTS site key (example: BVAS)
 site_id=111     - CUFTS site id (example: 111)
 resource_id=321 - CUFTS global resource id (example: 321)

 site_key or site_id is required, as is a resource_id to check against.

EOF
}
