#!/usr/bin/perl

# Copyright 2023 ByWater Solutions
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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;
use CGI qw ( -utf8 );

use C4::Context;
use C4::Output qw( output_html_with_http_headers );
use C4::Auth   qw( get_template_and_user );

use Koha::ItemTypes;
use Koha::Libraries;
use Koha::Library::FloatLimits;

my $input = CGI->new;

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "admin/float_limits.tt",
        query         => $input,
        type          => "intranet",
        flagsrequired => { parameters => 'manage_transfers' },
    }
);

my $op = $input->param('op');

if ( $op eq 'cud-set_float_limits' ) {
    my $schema    = Koha::Database->new()->schema();
    my @branches  = Koha::Libraries->search()->as_list;
    my @itemtypes = Koha::ItemTypes->search()->as_list;

    $schema->txn_do(
        sub {
            # Clear all existing float limits using DBIC
            Koha::Library::FloatLimits->delete;
            foreach my $branch (@branches) {
                foreach my $itemtype (@itemtypes) {
                    my $branchcode = $branch->id;
                    my $itype      = $itemtype->id;

                    my $limit = $input->param( "limit_" . $branchcode . "_" . $itype );

                    # Validate: must be empty or a non-negative integer
                    if ( $limit ne q{} && $limit =~ /^\d+$/ && $limit >= 0 ) {
                        Koha::Library::FloatLimit->new(
                            {
                                branchcode  => $branchcode,
                                itemtype    => $itype,
                                float_limit => $limit,
                            }
                        )->store();    # update or insert
                    }
                }
            }
            $template->param( float_limits_updated => 1 );
        }
    );
}

my $limits_hash = {};
my $limits      = Koha::Library::FloatLimits->search();
while ( my $l = $limits->next ) {
    $limits_hash->{ $l->branchcode }->{ $l->itemtype } = $l->float_limit;
}
$template->param( limits => $limits_hash );

output_html_with_http_headers $input, $cookie, $template->output;
