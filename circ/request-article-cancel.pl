#!/usr/bin/perl

# Copyright 2015
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

use C4::Output;
use C4::Auth;
use Koha::ArticleRequests;

my $cgi = new CGI;

my ( $template, $librarian, $cookie, $flags ) = get_template_and_user(
    {
        template_name   => "circ/request-article.tt",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => 'circulate_remaining_permissions' },
    }
);

my $id = $cgi->param('id');
my $ar = Koha::ArticleRequests->find($id);
$ar->cancel();
my $biblionumber = $ar->biblionumber;

print $cgi->redirect("/cgi-bin/koha/circ/request-article.pl?biblionumber=$biblionumber");
