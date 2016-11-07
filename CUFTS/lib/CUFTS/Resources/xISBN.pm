## CUFTS::Resources::xISBN
##
## Copyright Todd Holbrook - Simon Fraser University (2004)
##
## This file is part of CUFTS.
##
## CUFTS is free software; you can redistribute it and/or modify it under
## the terms of the GNU General Public License as published by the Free
## Software Foundation; either version 2 of the License, or (at your option)
## any later version.
##
## CUFTS is distributed in the hope that it will be useful, but WITHOUT ANY
## WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
## FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License along
## with CUFTS; if not, write to the Free Software Foundation, Inc., 59
## Temple Place, Suite 330, Boston, MA 02111-1307 USA

package CUFTS::Resources::xISBN;

use base qw(CUFTS::Resources);

use CUFTS::Exceptions;
use CUFTS::Util::Simple;

use LWP::UserAgent;
use HTTP::Request::Common;

use URI::Escape qw(uri_escape);
use String::Util qw(hascontent);
use JSON::XS qw( decode_json );
use Business::ISBN;

use strict;

sub services {
    return [ qw( metadata ) ];
}

sub has_title_list { return 0; }

sub local_resource_details       { return [  ] }
sub global_resource_details      { return [  ] }
sub overridable_resource_details { return [  ] }

sub help_template { return undef }

sub resource_details_help {
    return {
    };
}

sub get_records {
    my ( $class, $schema, $resource, $site, $request ) = @_;

    # All we use xISBN for right now is to get title information if all we're given is an ISBN

    if ( !hascontent( $request->isbn ) || hascontent( $request->title ) ) {
        return undef;
    }

    my $isbn = Business::ISBN->new($request->isbn);
    if ( !defined($isbn) || !$isbn->is_valid() ) {
        return undef;
    }

    my $isbn_string = $isbn->as_isbn13->as_string;

    my $cache_data = $schema->resultset('SearchCache')->search({
        type    => 'xisbn',
        query => $isbn_string,
    })->first;

    my $xisbn_data;
    if ( defined $cache_data ) {
        $xisbn_data = decode_json( $cache_data->result );
    }
    else {
        my $url = "http://xisbn.worldcat.org/webservices/xid/isbn/${isbn_string}?method=getMetadata&format=json&fl=*";
        $url =~ s/\{ISBN\}/$isbn_string/;

        my $ua = LWP::UserAgent->new();
        $ua->timeout(3);

        eval {
            my $response = $ua->get( $url );
            if ( !$response->is_success ) {
                return undef;
            }

            $xisbn_data = decode_json( $response->content );

            $cache_data = $schema->resultset('SearchCache')->create({
                type   => 'crossref',
                query  => $isbn_string,
                result => $response->content,
            });
        };
        if ($@) {
            warn "Unable to parse JSON from xISBN: $@\n";
            return undef;
        }
    }

    if ( ref $xisbn_data eq 'HASH' && exists $xisbn_data->{list} && scalar @{$xisbn_data->{list}} ) {
        my $item_data = $xisbn_data->{list}->[0];
        use Data::Dumper;
        warn(Dumper($item_data));

        if ( !hascontent($request->title) && hascontent($item_data->{title}) ) {
            $request->title( $item_data->{title} );
        }
        if ( !hascontent($request->pub) && hascontent($item_data->{publisher}) ) {
            $request->pub( $item_data->{publisher} );
        }
        if ( !hascontent($request->date) && hascontent($item_data->{year}) ) {
            $request->date( $item_data->{year} );
        }
        if ( !hascontent($request->au) && hascontent($item_data->{author}) ) {
            $request->au( $item_data->{author} );
        }
    }

    return undef;
}

sub can_getMetadata {
    my ( $class, $request ) = @_;

    return 0 if $request->genre ne 'book';

    return 1 if hascontent( $request->isbn );
    return 1 if hascontent( $request->title );

    return 0;
}

1;
