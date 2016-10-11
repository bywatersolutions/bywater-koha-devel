#! /usr/bin/perl

# Copyright 2006 SAN OUEST-PROVENCE et Paul POULAIN
# Copyright 2015 Koha Development Team
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
use C4::Context;
use C4::Auth;
use C4::Output;

use Koha::Cities;

my $input       = new CGI;
my $searchfield = $input->param('city_name') // q||;
my $cityid      = $input->param('cityid');
my $op          = $input->param('op') || 'list';
my @messages;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {   template_name   => "admin/cities.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { parameters => 'parameters_remaining_permissions' },
        debug           => 1,
    }
);

my $dbh = C4::Context->dbh;

if ( $op eq 'list' ) {
    my $cities = Koha::Cities->search( { city_name => { -like => "%$searchfield%" } } );
    $template->param( cities => $cities, );
}

$template->param(
    cityid      => $cityid,
    searchfield => $searchfield,
    messages    => \@messages,
    op          => $op,
);

output_html_with_http_headers $input, $cookie, $template->output;
