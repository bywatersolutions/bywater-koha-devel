#!/usr/bin/perl
#
# Copyright ByWater Solutions 2015
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use C4::Biblio qw( GetMarcFromKohaField );
use C4::Circulation qw( GetTransfers );
use C4::Context;
use C4::Koha qw( GetAuthorisedValues );
use C4::Items qw( GetItem );
use C4::Reserves qw( GetReserveStatus );
use C4::Search qw();
use Koha;
use Koha::Logger;

use Carp;
use Getopt::Long;
use Net::Z3950::SimpleServer;
use Pod::Usage;
use ZOOM;

use constant {
    UNIMARC_OID => '1.2.840.10003.5.1',
    USMARC_OID => '1.2.840.10003.5.10',
    MARCXML_OID => '1.2.840.10003.5.109.10'
};

use constant {
    ERR_TEMPORARY_ERROR => 2,
    ERR_PRESENT_OUT_OF_RANGE => 13,
    ERR_RECORD_TOO_LARGE => 16,
    ERR_NO_SUCH_RESULTSET => 30,
    ERR_SYNTAX_UNSUPPORTED => 230,
    ERR_DB_DOES_NOT_EXIST => 235,
};

=head1 SYNOPSIS

   z3950_responder.pl [-h|--help] [--man] [-a <pdufile>] [-v <loglevel>] [-l <logfile>] [-u <user>]
                      [-c <config>] [-t <minutes>] [-k <kilobytes>] [-d <daemon>] [-p <pidfile>]
                      [-C certfile] [-zKiDST1] [-m <time-format>] [-w <directory>] [--debug]
                      [--add-item-status=SUBFIELD] [--prefetch=NUM_RECORDS]
                      [<listener-addr>... ]

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief usage message and exits.

=item B<--man>

Displays manual page and exits.

=item B<--debug>

Turns on debug logging to the screen, and turns on single-process mode.

=item B<--add-item-status=SUBFIELD>

If given, adds item status information to the given subfield.

=item B<--add-status-multi-subfield>

With the above, instead of putting multiple item statuses in one subfield, adds a subfield for each
status string.

=item B<--prefetch=NUM_RECORDS>

Number of records to prefetch from Zebra. Defaults to 20.

=back

=head1 CONFIGURATION

The item status strings added by B<--add-item-status> can be configured with the B<Z3950_STATUS>
authorized value, using the following keys:

=over 4

=item AVAILABLE

=item CHECKED_OUT

=item LOST

=item NOT_FOR_LOAN

=item DAMAGED

=item WITHDRAWN

=item IN_TRANSIT

=item ON_HOLD

=back

=cut

my $add_item_status_subfield;
my $add_status_multi_subfield;
my $debug = 0;
my $help;
my $man;
my $prefetch = 20;
my @yaz_options;

sub add_yaz_option {
    my ( $opt_name, $opt_value ) = @_;

    push @yaz_options, "-$opt_name", "$opt_value";
}

GetOptions(
    '-h|help' => \$help,
    '--man' => \$man,
    '--debug' => \$debug,
    '--add-item-status=s' => \$add_item_status_subfield,
    '--add-status-multi-subfield' => \$add_status_multi_subfield,
    '--prefetch=i' => \$prefetch,
    # Pass through YAZ options.
    'a=s' => \&add_yaz_option,
    'v=s' => \&add_yaz_option,
    'l=s' => \&add_yaz_option,
    'u=s' => \&add_yaz_option,
    'c=s' => \&add_yaz_option,
    't=s' => \&add_yaz_option,
    'k=s' => \&add_yaz_option,
    'd=s' => \&add_yaz_option,
    'p=s' => \&add_yaz_option,
    'C=s' => \&add_yaz_option,
    'm=s' => \&add_yaz_option,
    'w=s' => \&add_yaz_option,
    'z' => \&add_yaz_option,
    'K' => \&add_yaz_option,
    'i' => \&add_yaz_option,
    'D' => \&add_yaz_option,
    'S' => \&add_yaz_option,
    'T' => \&add_yaz_option,
    '1' => \&add_yaz_option
) || pod2usage(2);

pod2usage(1) if $help;
pod2usage( -verbose => 2 ) if $man;

unshift @ARGV, @yaz_options;

# Turn off Yaz's built-in logging (can be turned back on if desired).
unshift @ARGV, '-v', 'none';

# If requested, turn on debugging.

if ( $debug ) {
    # Turn on single-process mode.
    unshift @ARGV, '-S';
}

my ($item_tag, $itemnumber_subfield) = GetMarcFromKohaField("items.itemnumber",'');

# We hardcode the strings for English so SOMETHING will work if the authorized value doesn't exist.

my $status_strings = {
    AVAILABLE => 'Available',
    CHECKED_OUT => 'Checked Out',
    LOST => 'Lost',
    NOT_FOR_LOAN => 'Not for Loan',
    DAMAGED => 'Damaged',
    WITHDRAWN => 'Withdrawn',
    IN_TRANSIT => 'In Transit',
    ON_HOLD => 'On Hold',
};

foreach my $val ( @{ GetAuthorisedValues( 'Z3950_STATUS' ) } ) {
    $status_strings->{ $val->{authorised_value} } = $val->{lib};
}

# Create and start the server.

my $z = Net::Z3950::SimpleServer->new(
    # Global context object. This is shared between processes, so it should not be modified.
    GHANDLE => {
        add_item_status_subfield => $add_item_status_subfield,
        add_status_multi_subfield => $add_status_multi_subfield,
        debug => $debug,
        item_tag => $item_tag,
        itemnumber_subfield => $itemnumber_subfield,
        num_to_prefetch => $prefetch,
        status_strings => $status_strings,
    },
    INIT => \&init_handler,
    SEARCH => \&search_handler,
    PRESENT => \&present_handler,
    FETCH => \&fetch_handler,
    CLOSE => \&close_handler,
);

$z->launch_server('z3950_responder.pl', @ARGV);

sub _set_error {
    my ( $args, $code, $msg ) = @_;
    ( $args->{ERR_CODE}, $args->{ERR_STR} ) = ( $code, $msg );

    $args->{HANDLE}->{logger}->info("[$args->{HANDLE}->{peer}]     returning error $code: $msg");
}

sub _set_error_from_zoom {
    my ( $args, $exception ) = @_;

    _set_error( $args, ERR_TEMPORARY_ERROR, 'Cannot connect to upstream server' );
    $args->{HANDLE}->{logger}->error(
        "Zebra upstream error: " .
        $exception->message() . " (" .
        $exception->code() . ") " .
        ( $exception->addinfo() // '' ) . " " .
        $exception->diagset()
    );
}

# This code originally went through C4::Search::getRecords, but had to use so many escape hatches
# that it was easier to directly connect to Zebra.
sub _start_search {
    my ( $config, $session, $args, $in_retry ) = @_;

    my $database = $args->{DATABASES}->[0];
    my ( $connection, $results );

    eval {
        $connection = C4::Context->Zconn(
            # We're depending on the caller to have done some validation.
            $database eq 'biblios' ? 'biblioserver' : 'authorityserver',
            0 # No, no async, doesn't really help much for single-server searching
        );

        $results = $connection->search_pqf( $args->{QUERY} );

        $session->{logger}->debug("[$session->{peer}]    retry successful") if ($in_retry);
    };
    if ($@) {
        die $@ if ( ref($@) ne 'ZOOM::Exception' );

        if ( $@->diagset() eq 'ZOOM' && $@->code() == 10004 && !$in_retry ) {
            $session->{logger}->debug("[$session->{peer}]     upstream server lost connection, retrying");
            return _start_search( $config, $session, $args, $in_retry );
        }

        _set_error_from_zoom( $args, $@ );
        $connection = undef;
    }

    return ( $connection, $results, $results ? $results->size() : -1 );
}

sub _prefetch_records {
    my ( $session, $resultset, $args, $start, $num_records ) = @_;

    eval {
        if ( $start + $num_records >= $resultset->{results}->size() ) {
            $num_records = $resultset->{results}->size() - $start;
        }

        $session->{logger}->debug("[$session->{peer}]     prefetching $num_records records starting at $start");

        $resultset->{results}->records( $start, $num_records, 0 );
    };
    if ($@) {
        die $@ if ( ref($@) ne 'ZOOM::Exception' );
        _set_error_from_zoom( $args, $@ );
        return;
    }
}

sub _fetch_record {
    my ( $session, $resultset, $args, $index, $num_to_prefetch ) = @_;

    my $record;

    eval {
        if ( !$resultset->{results}->record_immediate( $index ) ) {
            my $start = int( $index / $num_to_prefetch ) * $num_to_prefetch;

            if ( $start + $num_to_prefetch >= $resultset->{results}->size() ) {
                $num_to_prefetch = $resultset->{results}->size() - $start;
            }

            $session->{logger}->debug("[$session->{peer}]     fetch uncached, fetching $num_to_prefetch records starting at $start");

            $resultset->{results}->records( $start, $num_to_prefetch, 0 );
        }

        $record = $resultset->{results}->record_immediate( $index )->raw();
    };
    if ($@) {
        die $@ if ( ref($@) ne 'ZOOM::Exception' );
        _set_error_from_zoom( $args, $@ );
        return;
    } else {
        return $record;
    }
}

sub _close_resultset {
    my ( $resultset ) = @_;

    $resultset->{results}->destroy();
    # We can't destroy the connection, as it may be cached
}

sub init_handler {
    # Called when the client first connects.
    my ( $args ) = @_;

    my $config = $args->{GHANDLE};

    # This holds all of the per-connection state.
    my $session = {
        logger => Koha::Logger->get({ interface => 'z3950' }),
        peer => $args->{PEER_NAME},
        resultsets => {},
    };

    if ( $config->{debug} ) {
        $session->{logger}->debug_to_screen();
    }

    $args->{HANDLE} = $session;

    $args->{IMP_NAME} = "Koha";
    $args->{IMP_VER} = Koha::version;

    $session->{logger}->info("[$session->{peer}] connected");
}

sub search_handler {
    # Called when search is first sent.
    my ( $args ) = @_;

    my $database = $args->{DATABASES}->[0];
    if ( $database !~ /^(biblios|authorities)$/ ) {
        _set_error( ERR_DB_DOES_NOT_EXIST, 'No such database' );
        return;
    }

    my $config = $args->{GHANDLE};
    my $session = $args->{HANDLE};

    my $query = $args->{QUERY};
    $session->{logger}->info("[$session->{peer}] received search for '$query', (RS $args->{SETNAME})");

    my ( $connection, $results, $num_hits ) = _start_search( $config, $session, $args );
    return unless $connection;

    $args->{HITS} = $num_hits;
    my $resultset = $session->{resultsets}->{ $args->{SETNAME} } = {
        database => $database,
        connection => $connection,
        results => $results,
        query => $args->{QUERY},
        hits => $args->{HITS},
    };
}

sub _check_fetch {
    my ( $args, $resultset, $offset, $num_records ) = @_;

    if ( !defined( $resultset ) ) {
        _set_error( $args, ERR_NO_SUCH_RESULTSET, 'No such resultset' );
        return 0;
    }

    if ( $offset + $num_records > $resultset->{hits} )  {
        _set_error( $args, ERR_PRESENT_OUT_OF_RANGE, 'Fetch request out of range' );
        return 0;
    }

    return 1;
}

sub present_handler {
    # Called when a set of records is requested.
    my ( $args ) = @_;
    my $session = $args->{HANDLE};

    $session->{logger}->debug("[$session->{peer}] received present for $args->{SETNAME}, $args->{START}+$args->{NUMBER}");

    my $resultset = $session->{resultsets}->{ $args->{SETNAME} };
    # The offset comes across 1-indexed.
    my $offset = $args->{START} - 1;

    return unless _check_fetch( $args, $resultset, $offset, $args->{NUMBER} );

    # Ignore if request is only for one record; our own prefetching will probably do a better job.
    _prefetch_records( $session, $resultset, $args, $offset, $args->{NUMBER} ) if ( $args->{NUMBER} > 1 );
}

sub fetch_handler {
    # Called when a given record is requested.
    my ( $args ) = @_;
    my $config = $args->{GHANDLE};
    my $session = $args->{HANDLE};

    $session->{logger}->debug("[$session->{peer}] received fetch for $args->{SETNAME}, record $args->{OFFSET}");
    my $form_oid = $args->{REQ_FORM} // '';
    my $composition = $args->{COMP} // '';
    $session->{logger}->debug("[$session->{peer}]     form OID $form_oid, composition $composition");

    my $resultset = $session->{resultsets}->{ $args->{SETNAME} };
    # The offset comes across 1-indexed.
    my $offset = $args->{OFFSET} - 1;

    return unless _check_fetch( $args, $resultset, $offset, 1 );

    $args->{LAST} = 1 if ( $offset == $resultset->{hits} - 1 );

    my $record = _fetch_record( $session, $resultset, $args, $offset, $config->{num_to_prefetch} );
    return unless $record;

    $record = C4::Search::new_record_from_zebra(
        $resultset->{database} eq 'biblios' ? 'biblioserver' : 'authorityserver',
        $record
    );

    if ( $config->{add_item_status_subfield} ) {
        my $tag = $config->{item_tag};
        my $itemnumber_subfield = $config->{itemnumber_subfield};
        my $add_subfield = $config->{add_item_status_subfield};
        my $status_strings = $config->{status_strings};

        foreach my $field ( $record->field($tag) ) {
            my $itemnumber = $field->subfield($itemnumber_subfield);
            next unless $itemnumber;

            my $item = GetItem( $itemnumber );
            my @statuses;

            if ( $item->{onloan} ) {
                push @statuses, $status_strings->{CHECKED_OUT};
            }

            if ( $item->{itemlost} ) {
                push @statuses, $status_strings->{LOST};
            }

            if ( $item->{notforloan} ) {
                push @statuses, $status_strings->{NOT_FOR_LOAN};
            }

            if ( $item->{damaged} ) {
                push @statuses, $status_strings->{DAMAGED};
            }

            if ( $item->{withdrawn} ) {
                push @statuses, $status_strings->{WITHDRAWN};
            }

            if ( scalar( GetTransfers( $itemnumber ) ) ) {
                push @statuses, $status_strings->{IN_TRANSIT};
            }

            if ( GetReserveStatus( $itemnumber ) ne '' ) {
                push @statuses, $status_strings->{ON_HOLD};
            }

            $field->delete_subfield( code => $itemnumber_subfield );

            if ( $config->{add_status_multi_subfield} ) {
                $field->add_subfields( map { ( $add_subfield, $_ ) } ( @statuses ? @statuses : $status_strings->{AVAILABLE} ) );
            } else {
                $field->add_subfields( $add_subfield, @statuses ? join( ', ', @statuses ) : $status_strings->{AVAILABLE} );
            }
        }
    }

    if ( $form_oid eq MARCXML_OID && $composition eq 'marcxml' ) {
        $args->{RECORD} = $record->as_xml_record();
    } elsif ( ( $form_oid eq USMARC_OID || $form_oid eq UNIMARC_OID ) && ( !$composition || $composition eq 'F' ) ) {
        $args->{RECORD} = $record->as_usmarc();
    } else {
        _set_error( $args, ERR_SYNTAX_UNSUPPORTED, "Unsupported syntax/composition $form_oid/$composition" );
        return;
    }
}

sub close_handler {
    my ( $args ) = @_;

    my $session = $args->{HANDLE};

    foreach my $resultset ( values %{ $session->{resultsets} } ) {
        _close_resultset( $resultset );
    }
}
