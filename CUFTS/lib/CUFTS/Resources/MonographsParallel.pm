## CUFTS::Resources::MonographsParallel
##
## Copyright Todd Holbrook - Simon Fraser University (2003)
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

package CUFTS::Resources::MonographsParallel;

use base qw(CUFTS::Resources::Base::Monographs);
use CUFTS::Exceptions;
use CUFTS::Util::Simple;
use CUFTS::Result;

use String::Util qw(trim hascontent);
use URI::Escape qw(uri_escape);

use strict;

sub services {
    return [ qw( holdings ) ];
}

sub local_resource_details {
    return [qw(url_base)];
}

sub get_records {
    my ( $class, $schema, $resource, $site, $request ) = @_;
    return [ { id => 'dummy record' } ];
}

sub search_getHoldings {
    return shift->get_records( @_ );
}

sub build_linkHoldings {
    my ( $class, $schema, $records, $resource, $site, $request ) = @_;

    my %test_site_map = (
        BVAS => 'Simon Fraser University',
        ALU  => 'University of Alberta',
    );

    my $title = $request->title;
    my $isbn  = $request->isbn;

    my @results;
    foreach my $test_site ( 'BVAS', 'ALU' ) {
        my $api_url = "http://api.lib.sfu.ca/holdings_search/search?site=$test_site";
        if ( hascontent($title) ) {
            $api_url .= '&title=' . uri_escape($title);
        }
        if ( hascontent($isbn) ) {
            $api_url .= '&isbn=' . uri_escape($isbn);
        }

        push @results, {
            id   => $test_site,
            name => $test_site_map{$test_site},
            url  => $api_url,
        }
    }

    my $result = new CUFTS::Result(
        {
            # url => $url,
            extra_data => {
                targets => \@results,
            },
        }
    );


    return [ $result ];
}

1;
