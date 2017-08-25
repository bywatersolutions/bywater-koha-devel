#!/usr/bin/perl

# Copyright Katipo Communications 2002
# Copyright Biblibre 2007,2010
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
use C4::Members;
use C4::Auth;
use C4::Output;
use Koha::Patrons;
use Koha::Plugins;

my $query = new CGI;
my ( $template, $borrowernumber, $cookie ) = get_template_and_user(
    {
        template_name   => "opac-account.tt",
        query           => $query,
        type            => "opac",
        authnotrequired => 0,
        debug           => 1,
    }
);

my $patron = Koha::Patrons->find( $borrowernumber );
my $category = $patron->category;
my $borrower= $patron->unblessed;
$borrower->{description} = $category->description;
$borrower->{category_type} = $category->category_type;
$template->param( BORROWER_INFO => $borrower );

#get account details
my ( $total , $accts, $numaccts) = GetMemberAccountRecords( $borrowernumber );

for ( my $i = 0 ; $i < $numaccts ; $i++ ) {
    $accts->[$i]{'amount'} = sprintf( "%.2f", $accts->[$i]{'amount'} || '0.00');
    if ( $accts->[$i]{'amount'} >= 0 ) {
        $accts->[$i]{'amountcredit'} = 1;
    }
    $accts->[$i]{'amountoutstanding'} =
      sprintf( "%.2f", $accts->[$i]{'amountoutstanding'} || '0.00' );
    if ( $accts->[$i]{'amountoutstanding'} >= 0 ) {
        $accts->[$i]{'amountoutstandingcredit'} = 1;
    }
}

# add the row parity
my $num = 0;
foreach my $row (@$accts) {
    $row->{'even'} = 1 if $num % 2 == 0;
    $row->{'odd'}  = 1 if $num % 2 == 1;
    $num++;
}

$template->param(
    ACCOUNT_LINES => $accts,
    total         => sprintf( "%.2f", $total ),
    accountview   => 1,
    message       => scalar $query->param('message') || q{},
    message_value => scalar $query->param('message_value') || q{},
    payment       => scalar $query->param('payment') || q{},
    payment_error => scalar $query->param('payment-error') || q{},
);

my $plugins_enabled = C4::Context->preference('UseKohaPlugins') && C4::Context->config("enable_plugins");
if ( $plugins_enabled ) {
	my @plugins = Koha::Plugins->new()->GetPlugins({
		method => 'opac_online_payment',
	});
    # Only pass in plugins where opac online payment is enabled
    @plugins = grep { $_->opac_online_payment } @plugins;
	$template->param( plugins => \@plugins );
}

output_html_with_http_headers $query, $cookie, $template->output, undef, { force_no_caching => 1 };
