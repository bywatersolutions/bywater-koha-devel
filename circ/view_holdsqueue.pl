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
# along with Koha; if not, see <http://www.gnu.org/licenses>.


=head1 view_holdsqueue

This script displays items in the tmp_holdsqueue table

=cut

use Modern::Perl;
use CGI qw ( -utf8 );
use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers pagination_bar );
use C4::HoldsQueue qw( GetHoldsQueueItems );
use Koha::BiblioFrameworks;
use Koha::ItemTypes;

my $query = CGI->new;
my ( $template, $loggedinuser, $cookie, $flags ) = get_template_and_user(
    {
        template_name   => "circ/view_holdsqueue.tt",
        query           => $query,
        type            => "intranet",
        flagsrequired   => { circulate => "circulate_remaining_permissions" },
    }
);

my $params = $query->Vars;
my $run_report     = $params->{'run_report'};
my $branchlimit    = $params->{'branchlimit'};
my $limit          = $params->{'limit'} || 20;
my $page           = $params->{'page'}  || 1;

if ( $run_report ) {
    my ( $items, $total ) = GetHoldsQueueItems( $branchlimit, $limit, $page );

    my $pages = int( $total / $limit ) + ( ( $total % $limit ) > 0 ? 1 : 0 );
    warn "LIMIT: $limit";
    warn "PAGES: $pages";
    $template->param(
        branchlimit    => $branchlimit,
        total          => $total,
        itemsloop      => $items,
        run_report     => $run_report,
        page           => $page,
        limit          => $limit,
        pagination_bar => pagination_bar(
            'view_holdsqueue.pl',
            $pages,
            $page,
            'page',
            { branchlimit => $branchlimit, limit => $limit, run_report => 1, }
        ),
    );
}

# Checking if there is a Fast Cataloging Framework
$template->param( fast_cataloging => 1 ) if Koha::BiblioFrameworks->find( 'FA' );

# writing the template
output_html_with_http_headers $query, $cookie, $template->output;
