#!/usr/bin/perl
# vim: et ts=4 sw=4
# Copyright BibLibre 
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


# This script clones issuing rules from a library to another
# parameters : 
#  - frombranch : the branch we want to clone issuing rules from
#  - tobranch   : the branch we want to clone issuing rules to
#
# The script can be called with one of the parameters, both or none

use Modern::Perl;
use CGI qw ( -utf8 );
use C4::Context;
use C4::Output;
use C4::Auth;
use C4::Koha;
use C4::Debug;
use Koha::CirculationRules;

my $input = new CGI;
my $dbh = C4::Context->dbh;

my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "admin/clone-rules.tt",
                            query => $input,
                            type => "intranet",
                            flagsrequired => {parameters => 'manage_circ_rules'},
                            debug => 1,
                            });

my $frombranch = $input->param("frombranch");
my $tobranch   = $input->param("tobranch");

$template->param(frombranch     => $frombranch)                if ($frombranch);
$template->param(tobranch       => $tobranch)                  if ($tobranch);

if ($frombranch && $tobranch) {

    my $error;	

    # First, we create a temporary table with the rules we want to clone
    my $query = "CREATE TEMPORARY TABLE tmpissuingrules ENGINE=memory SELECT * FROM issuingrules WHERE branchcode=?";
    my $sth = $dbh->prepare($query);
    my $res = $sth->execute($frombranch);
    $error = 1 unless ($res);

    if (!$error) {
	# We modify these rules according to the new branchcode
	$query = "UPDATE tmpissuingrules SET branchcode=? WHERE branchcode=?";
	$sth = $dbh->prepare($query);
	$res = $sth->execute($tobranch, $frombranch);
	$error = 1 unless ($res);
    }

    if (!$error) {
	# We delete the rules for the existing branchode
	$query = "DELETE FROM issuingrules WHERE branchcode=?";
	$sth = $dbh->prepare($query);
	$res = $sth->execute($tobranch);
	$error = 1 unless ($res);
    }


    if (!$error) {
	# We insert the new rules from our temporary table
	$query = "INSERT INTO issuingrules SELECT * FROM tmpissuingrules WHERE branchcode=?";
	$sth = $dbh->prepare($query);
	$res = $sth->execute($tobranch);
	$error = 1 unless ($res);
    }

    # Finally, we delete our temporary table
    $query = "DROP TABLE tmpissuingrules";
    $sth = $dbh->prepare($query);
    $res = $sth->execute();

    # For already moved rules, maxissueqty and maxonsiteissueqty
    Koha::CirculationRules->search({branchcode => $tobranch})->delete;
    my $rules = Koha::CirculationRules->search({ branchcode => $frombranch eq '*' ? undef : $frombranch });
    while ( my $rule = $rules->next ) {
        my $cloned_rule = $rule->unblessed;
        $cloned_rule->{branchcode} = $tobranch;
        delete $cloned_rule->{id};
        Koha::CirculationRule->new( $cloned_rule )->store;
    }

    $template->param(result => "1");
    $template->param(error  => $error);
}



output_html_with_http_headers $input, $cookie, $template->output;

