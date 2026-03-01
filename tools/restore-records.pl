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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use CGI  qw ( -utf8 );
use JSON qw( encode_json );

use C4::Auth   qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use Koha::Patrons;

my $input = CGI->new;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "tools/restore-records.tt",
        query         => $input,
        type          => "intranet",
        flagsrequired => { editcatalogue => 'records_restore' },
    }
);

my $patron                   = Koha::Patrons->find($loggedinuser);
my @libraries_where_can_edit = $patron->libraries_where_can_edit_items;

$template->param(
    libraries_where_can_edit_json => encode_json( \@libraries_where_can_edit ),
);

output_html_with_http_headers $input, $cookie, $template->output;
