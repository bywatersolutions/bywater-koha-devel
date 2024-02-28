#!/usr/bin/perl

# Copyright 2012 Catalyst IT
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

use C4::Auth qw( checkauth );
use C4::Output;


use C4::Calendar;

my $input               = CGI->new;
my $op                  = $input->param('op') // q{};
my $dbh                 = C4::Context->dbh();

checkauth($input, 0, {tools=> 'edit_calendar'}, 'intranet');

my $branchcode          = $input->param('branchcode');
my $from_branchcode     = $input->param('from_branchcode');

if ( $op eq 'cud-copy' ) {
    C4::Calendar->new( branchcode => $from_branchcode )->copy_to_branch($branchcode) if $from_branchcode && $branchcode;
}

print $input->redirect("/cgi-bin/koha/tools/holidays.pl?branch=".($branchcode || $from_branchcode));
