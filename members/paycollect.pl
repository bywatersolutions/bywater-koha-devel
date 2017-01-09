#!/usr/bin/perl
# Copyright 2009,2010 PTFS Inc.
# Copyright 2011 PTFS-Europe Ltd
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

use strict;
use warnings;
use URI::Escape;
use C4::Context;
use C4::Auth;
use C4::Output;
use CGI qw ( -utf8 );
use C4::Members;
use C4::Members::Attributes qw(GetBorrowerAttributes);
use C4::Accounts;
use C4::Koha;
use Koha::Patron::Images;
use Koha::Account;

use Koha::Patron::Categories;

my $input = CGI->new();

my $updatecharges_permissions = $input->param('writeoff_individual') ? 'writeoff' : 'remaining_permissions';
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {   template_name   => 'members/paycollect.tt',
        query           => $input,
        type            => 'intranet',
        authnotrequired => 0,
        flagsrequired   => { borrowers => 1, updatecharges => $updatecharges_permissions },
        debug           => 1,
    }
);

# get borrower details
my $borrowernumber = $input->param('borrowernumber');
my $borrower       = GetMember( borrowernumber => $borrowernumber );
my $user           = $input->remote_user;

my $branch         = C4::Context->userenv->{'branch'};

my ( $total_due, $accts, $numaccts ) = GetMemberAccountRecords($borrowernumber);
my $total_paid = $input->param('paid');

my $individual   = $input->param('pay_individual');
my $writeoff     = $input->param('writeoff_individual');
my $select_lines = $input->param('selected');
my $select       = $input->param('selected_accts');
my $payment_note = uri_unescape $input->param('payment_note');
my $accountno;
my $accountlines_id;

if ( $individual || $writeoff ) {
    if ($individual) {
        $template->param( pay_individual => 1 );
    } elsif ($writeoff) {
        $template->param( writeoff_individual => 1 );
    }
    my $accounttype       = $input->param('accounttype');
    $accountlines_id       = $input->param('accountlines_id');
    my $amount            = $input->param('amount');
    my $amountoutstanding = $input->param('amountoutstanding');
    $accountno = $input->param('accountno');
    my $itemnumber  = $input->param('itemnumber');
    my $description  = $input->param('description');
    my $title        = $input->param('title');
    my $notify_id    = $input->param('notify_id');
    my $notify_level = $input->param('notify_level');
    $total_due = $amountoutstanding;
    $template->param(
        accounttype       => $accounttype,
        accountlines_id    => $accountlines_id,
        accountno         => $accountno,
        amount            => $amount,
        amountoutstanding => $amountoutstanding,
        title             => $title,
        itemnumber        => $itemnumber,
        individual_description => $description,
        notify_id         => $notify_id,
        notify_level      => $notify_level,
        payment_note    => $payment_note,
    );
} elsif ($select_lines) {
    $total_due = $input->param('amt');
    $template->param(
        selected_accts => $select_lines,
        amt            => $total_due,
        selected_accts_notes => scalar $input->param('notes'),
    );
}

if ( $total_paid and $total_paid ne '0.00' ) {
    if ( $total_paid < 0 or $total_paid > $total_due ) {
        $template->param(
            error_over => 1,
            total_due => $total_due
        );
    } else {
        if ($individual) {
            if ( $total_paid == $total_due ) {
                my $line = Koha::Account::Lines->find($accountlines_id);
                Koha::Account->new( { patron_id => $borrowernumber } )->pay(
                    {
                        lines      => [$line],
                        amount     => $total_paid,
                        library_id => $branch,
                        note       => $payment_note
                    }
                );
            } else {
                makepartialpayment( $accountlines_id, $borrowernumber, $accountno, $total_paid,
                    $user, $branch, $payment_note );
            }
            print $input->redirect(
                "/cgi-bin/koha/members/pay.pl?borrowernumber=$borrowernumber");
        } else {
            if ($select) {
                if ( $select =~ /^([\d,]*).*/ ) {
                    $select = $1;    # ensure passing no junk
                }
                my @acc = split /,/, $select;
                my $note = $input->param('selected_accts_notes');
                recordpayment_selectaccts( $borrowernumber, $total_paid, \@acc, $note );
            } else {
                my $note = $input->param('selected_accts_notes');
                Koha::Account->new( { patron_id => $borrowernumber } )
                  ->pay( { amount => $total_paid, note => $note } );
            }

            print $input->redirect(
"/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber"
            );
        }
    }
} else {
    $total_paid = '0.00';    #TODO not right with pay_individual
}

borrower_add_additional_fields($borrower, $template);

$template->param(%$borrower);

$template->param(
    borrowernumber => $borrowernumber,    # some templates require global
    borrower      => $borrower,
    categoryname  => $borrower->{description},
    total         => $total_due,
    activeBorrowerRelationship => (C4::Context->preference('borrowerRelationship') ne ''),
    RoutingSerials => C4::Context->preference('RoutingSerials'),
    ExtendedPatronAttributes => C4::Context->preference('ExtendedPatronAttributes'),
);

output_html_with_http_headers $input, $cookie, $template->output;

sub borrower_add_additional_fields {
    my ( $b_ref, $template ) = @_;

# some borrower info is not returned in the standard call despite being assumed
# in a number of templates. It should not be the business of this script but in lieu of
# a revised api here it is ...
    if ( $b_ref->{category_type} eq 'C' ) {
        my $patron_categories = Koha::Patron::Categories->search_limited({ category_type => 'A' }, {order_by => ['categorycode']});
        $template->param( 'CATCODE_MULTI' => 1) if $patron_categories->count > 1;
        $template->param( 'catcode' => $patron_categories->next )  if $patron_categories->count == 1;
    } elsif ( $b_ref->{category_type} eq 'A' ) {
        $b_ref->{adultborrower} = 1;
    }

    my $patron_image = Koha::Patron::Images->find($b_ref->{borrowernumber});
    $template->param( picture => 1 ) if $patron_image;

    if (C4::Context->preference('ExtendedPatronAttributes')) {
        $b_ref->{extendedattributes} = GetBorrowerAttributes($b_ref->{borrowernumber});
    }

    return;
}
