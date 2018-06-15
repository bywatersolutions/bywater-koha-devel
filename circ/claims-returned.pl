#!/usr/bin/perl

# Copyright 2018 ByWater Solutions
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

use Koha::Checkouts::ReturnClaims;
use Koha::Checkouts;

my $cgi = new CGI;

checkauth( $cgi, 0, { circulate => 'circulate_remaining_permissions' }, 'intranet' );

my $destination    = scalar $cgi->param('destination');
my $borrowernumber = scalar $cgi->param('borrowernumber');
my $action         = scalar $cgi->param('action') || 'make';

if ( $action eq 'make' ) {
    my @checkout_ids = $cgi->multi_param('issue_id');
    my $notes        = scalar $cgi->param('notes');
    my $charge       = scalar $cgi->param('charge');

    foreach my $i (@checkout_ids) {
        my $checkout = Koha::Checkouts->find($i);
        next unless $checkout;
        $checkout->claim_returned(
            {
                charge => $charge,
                notes  => $notes,
            }
        );
    }
}
elsif ( $action eq 'resolve' ) {
    my @ids = $cgi->multi_param('id');

    foreach my $id (@ids) {
        my $resolution = $cgi->param("resolution_$id");
        next unless $resolution;

        my $claim = Koha::Checkouts::ReturnClaims->find($id);
        $claim->resolve( { resolution => $resolution } );
    }
}
elsif ( $action eq 'notes-edit' ) {
    my $id    = $cgi->param('id');
    my $notes = $cgi->param('notes');

    my $claim = Koha::Checkouts::ReturnClaims->find($id);
    $claim->notes($notes);
    $claim->store();
}

my $url =
  $destination eq 'circ'
  ? "/cgi-bin/koha/circ/circulation.pl?borrowernumber=$borrowernumber"
  : "/cgi-bin/koha/members/moremember.pl?borrowernumber=$borrowernumber";
$url .= '#relreturn-claims' unless $action eq 'make';

print $cgi->redirect($url);
