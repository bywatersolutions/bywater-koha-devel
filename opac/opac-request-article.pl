#!/usr/bin/perl

# Copyright ByWater Solutions 2015
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

use CGI qw ( -utf8 );

use C4::Auth;
use C4::Output;

use Koha::Biblios;
use Koha::Borrowers;

my $cgi = new CGI;

my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-request-article.tt",
        query           => $cgi,
        type            => "opac",
        authnotrequired => 0,
        debug           => 1,
    }
);

my $biblionumber = $cgi->param('biblionumber');

my $biblio = Koha::Biblios->find($biblionumber);
my $patron = Koha::Borrowers->find($borrowernumber);

$template->param(
    biblio => $biblio,
    patron => $patron,
);

output_html_with_http_headers $cgi, $cookie, $template->output;
