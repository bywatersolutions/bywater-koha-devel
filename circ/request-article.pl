#!/usr/bin/perl

# Copyright 2015 ByWater Solutions
#
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

use C4::Output;
use C4::Auth;
use C4::Utils::DataTables::Members;
use Koha::Biblios;
use Koha::Borrowers;
use Koha::ArticleRequests;

my $input = new CGI;

my ( $template, $borrowernumber, $cookie, $flags ) = get_template_and_user(
    {
        template_name   => "circ/request-article.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => 'circulate_remaining_permissions' },
    }
);

my $biblionumber      = $input->param('biblionumber');
my $patron_cardnumber = $input->param('patron_cardnumber');
my $patron_id         = $input->param('patron_id');

my $biblio = Koha::Biblios->find($biblionumber);
my $patron = Koha::Borrowers->find( $patron_id ? $patron_id : { cardnumber => $patron_cardnumber } );

if (!$patron && $patron_cardnumber) {
    my $results = C4::Utils::DataTables::Members::search(
        {
            searchmember => $patron_cardnumber,
            dt_params    => { iDisplayLength => -1 },
        }
    );

    my $patrons = $results->{patrons};

    if ( scalar @$patrons == 1 ) {
        $patron = Koha::Borrowers->find( $patrons->[0]->{borrowernumber} );
    }
    elsif (@$patrons) {
        $template->param( patrons => $patrons );
    }
    else {
        $template->param( no_patrons_found => $patron_cardnumber );
    }
}

$template->param(
    biblio => $biblio,
    patron => $patron,
);

output_html_with_http_headers $input, $cookie, $template->output;
