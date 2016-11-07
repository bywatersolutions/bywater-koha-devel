#!/usr/local/bin/perl

use lib qw (lib);

use strict;

use MARC::Batch;
use MARC::Record;
use MARC::Field;
MARC::Field->allow_controlfield_tags('FMT', 'LDX', 'LKR', 'CAT');    

my $FATAL_ERRORS = 1;

$MARC::Record::DEBUG = 1;

my $batch = MARC::Batch->new('USMARC', @ARGV);
$batch->strict_off();

my $count = 0;
while ( read_record($batch) ) {
    $count++;
    warn "- ${count} ---------------------------------------------------\n";
}

sub read_record {
    my ( $batch ) = @_;

    my $record;
    eval {
        $record = $batch->next();
        print STDERR "LEADER: ", $record->leader, "\n";
    };
    if ( $@ ) {
        if ( $FATAL_ERRORS ) {
            die($@)
        }
        else {
            warn( $@ );
            warn( 'Fatal errors is off, skipping record.' );
            $record = read_record($batch);
        }
    }
    
    return $record;
}