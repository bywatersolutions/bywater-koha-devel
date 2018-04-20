#!/usr/bin/perl

# Copyright ByWater Solutions 2017
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
use C4::Context;
use Koha::Patrons;

my $cgi = new CGI;

my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
    {
        template_name   => "members/merge-patrons.tt",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { borrowers => 1 },
        debug           => 1,
    }
);

my $action = $cgi->param('action') || 'show';
my @ids = $cgi->multi_param('id');

if ( $action eq 'show' ) {
    my $patrons =
      Koha::Patrons->search( { borrowernumber => { -in => \@ids } } );
    $template->param( patrons => $patrons );
} elsif ( $action eq 'merge' ) {
    my $keeper = $cgi->param('keeper');
    my $results = Koha::Patrons->merge( { keeper => $keeper, patrons => \@ids } );
    $template->param( results => $results );
}

$template->param( action => $action );

output_html_with_http_headers $cgi, $cookie, $template->output;

1;
