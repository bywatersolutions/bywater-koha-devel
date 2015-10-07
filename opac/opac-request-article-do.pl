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

use Koha::ArticleRequest;

my $cgi = new CGI;

my ( $userid, $cookie, $sessionID ) = checkauth( $cgi, 0, {}, 'opac' );
my $borrowernumber = C4::Context->userenv->{'number'};

my $biblionumber = $cgi->param('biblionumber');
my $branchcode   = $cgi->param('branchcode');

my $itemnumber = $cgi->param('itemnumber') || undef;
my $title      = $cgi->param('title')      || undef;
my $author     = $cgi->param('author')     || undef;
my $volume     = $cgi->param('volume')     || undef;
my $issue      = $cgi->param('issue')      || undef;
my $date       = $cgi->param('date')       || undef;
my $pages      = $cgi->param('pages')      || undef;
my $chapters   = $cgi->param('chapters')   || undef;

my $ar = Koha::ArticleRequest->new(
    {
        borrowernumber => $borrowernumber,
        biblionumber   => $biblionumber,
        branchcode     => $branchcode,
        itemnumber     => $itemnumber,
        title          => $title,
        author         => $author,
        volume         => $volume,
        issue          => $issue,
        date           => $date,
        pages          => $pages,
        chapters       => $chapters,
    }
)->store();

print $cgi->redirect("/cgi-bin/koha/opac-user.pl#opac-user-article-requests");
