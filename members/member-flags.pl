#!/usr/bin/perl

# Copyright 2017 ByWater Solutions;
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
use C4::Context;
use C4::Members;
use C4::Members::Attributes qw(GetBorrowerAttributes);

use Koha::Patrons;
use Koha::Patron::Images;
use Koha::Patron::Categories;

use Koha::Token;
use Koha::Permissions;

my $input = new CGI;

my $flagsrequired = { permissions => 1 };
my $borrowernumber = $input->param('borrowernumber');

my $patron = Koha::Patrons->find($borrowernumber);

my $category_type = $patron->category->category_type;
my $bor           = $patron->unblessed;
if ( $category_type eq 'S' ) {
    $flagsrequired->{'staffaccess'} = 1;
}
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "members/member-flags.tt",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => $flagsrequired,
        debug           => 1,
    }
);

my $logged_in_user = Koha::Patrons->find( $loggedinuser ) or die "Not logged in";
output_and_exit_if_error( $input, $cookie, $template, { module => 'members', logged_in_user => $logged_in_user, current_patron => $patron } );

if ( $input->param('set_permissions') ) { # update permissions

    die "Wrong CSRF token"
      unless Koha::Token->new->check_csrf(
        {
            session_id => scalar $input->cookie('CGISESSID'),
            token      => scalar $input->param('csrf_token'),
        }
      );

    my @permissions = $input->multi_param('permission');

    $patron->set_permissions( { permissions => \@permissions } );

    print $input->redirect(
        "/cgi-bin/koha/members/moremember.pl?borrowernumber=$borrowernumber");
}
else { # fetch for display
    my $permissions = Koha::Permissions->search( { parent => undef } );
    $template->param(
        patron      => $patron,
        permissions => $permissions,
    );

    # Patron details boilerplate for patron related templates
    if ( $category_type eq 'C' ) {
        my $patron_categories =
          Koha::Patron::Categories->search_limited( { category_type => 'A' },
            { order_by => ['categorycode'] } );
        $template->param( 'CATCODE_MULTI' => 1 )
          if $patron_categories->count > 1;
        $template->param( 'catcode' => $patron_categories->next )
          if $patron_categories->count == 1;
    }

    $template->param( adultborrower => 1 ) if ( $category_type =~ /^(A|I)$/ );
    $template->param( picture       => 1 ) if $patron->image;

    if ( C4::Context->preference('ExtendedPatronAttributes') ) {
        my $attributes = GetBorrowerAttributes( $bor->{'borrowernumber'} );
        $template->param(
            ExtendedPatronAttributes => 1,
            extendedattributes       => $attributes
        );
    }

    $template->param(
        borrowernumber => $bor->{'borrowernumber'},
        cardnumber     => $bor->{'cardnumber'},
        surname        => $bor->{'surname'},
        firstname      => $bor->{'firstname'},
        othernames     => $bor->{'othernames'},
        categorycode   => $bor->{'categorycode'},
        category_type  => $category_type,
        categoryname   => $bor->{'description'},
        address        => $bor->{address},
        address2       => $bor->{'address2'},
        streettype     => $bor->{streettype},
        city           => $bor->{'city'},
        state          => $bor->{'state'},
        zipcode        => $bor->{'zipcode'},
        country        => $bor->{'country'},
        phone          => $bor->{'phone'},
        phonepro       => $bor->{'phonepro'},
        mobile         => $bor->{'mobile'},
        email          => $bor->{'email'},
        emailpro       => $bor->{'emailpro'},
        branchcode     => $bor->{'branchcode'},
        is_child       => ( $category_type eq 'C' ),
        RoutingSerials => C4::Context->preference('RoutingSerials'),
        csrf_token     => Koha::Token->new->generate_csrf(
            { session_id => scalar $input->cookie('CGISESSID'), }
        ),
    );

    output_html_with_http_headers $input, $cookie, $template->output;

}
