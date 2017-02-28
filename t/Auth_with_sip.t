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

use Modern::Perl;

use Test::More tests => 9;

use_ok('C4::Auth_with_sip');
can_ok( 'C4::Auth_with_sip', 'checkpw_sip' );

my $sip_message =
q{64              00120170516    103344000000000001000000000000AOMPL|AA9876543210|AEKyle M. Hall|BLY|CQY|CC3|BD123 Liberty Ave Natrona Heights PA 15065|BEkyle@kylehall.info|BF1234567890|PB19810610|PCST|PIY|AFGreetings from Koha. |}
  . "\n";
my $sip_hashref_expected = {
    'BL'            => 'Y',
    'AA'            => '9876543210',
    'AF'            => 'Greetings from Koha. ',
    'PI'            => 'Y',
    'patron_status' => {
        'too_many_items_overdue'            => ' ',
        'too_many_items_lost'               => ' ',
        'too_many_claims_of_items_returned' => ' ',
        'recall_overdue'                    => ' ',
        'excessive_outstanding_fees'        => ' ',
        'hold_privileges_denied'            => ' ',
        'too_many_items_billed'             => ' ',
        'excessive_outstanding_fines'       => ' ',
        'too_many_renewals'                 => ' ',
        'renewal_privileges_denied'         => ' ',
        'recall_privileges_denied'          => ' ',
        'charge_privileges_denied'          => ' ',
        'card_reported_lost'                => ' ',
        'too_many_items_charged'            => ' '
    },
    'PC'               => 'ST',
    'hold_items_count' => '0000',
    'CQ'               => 'Y',
    'PB'               => '19810610',
    'CC'               => '3',
    'AE'               => 'Kyle M. Hall',
    'BE'               => 'kyle@kylehall.info',
    'BF'               => '1234567890',
    'BD'               => '123 Liberty Ave Natrona Heights PA 15065'
};
my $sip_hashref = C4::Auth_with_sip::sip_message_to_hashref($sip_message);
is_deeply( $sip_hashref, $sip_hashref_expected,
    'SIP message converted to hashref correctly' );

my $servers = [
    { priority => 1, prefix => 'AAA' },
    { priority => 2, prefix => 'BBB' },
    { priority => 3, prefix => 'CCC' },
    { priority => 4, prefix => undef },
    { priority => 4, prefix => 'XXX' },
];
my $server = C4::Auth_with_sip::select_server( 'AAA123', $servers );
is( $server->{priority}, 1, 'Got correct server with prefix AAA' );
$server = C4::Auth_with_sip::select_server( 'BBB123', $servers );
is( $server->{priority}, 2, 'Got correct server with prefix BBB' );
$server = C4::Auth_with_sip::select_server( 'CCC123', $servers );
is( $server->{priority}, 3, 'Got correct server with prefix CCC' );
$server = C4::Auth_with_sip::select_server( '123', $servers );
is( $server->{priority}, 4, 'Got correct server with no prefix' );
$server = C4::Auth_with_sip::select_server( 'XXX123', $servers );
is( $server->{priority}, 4,
    'Got correct server with prefix XXX, server with no prefix is a catch-all'
);

$server = {
    'precedence' => '1',
    'prefix'     => 'MPL',
    'mapping'    => {
        'categorycode' => {
            'content' => 'PT',
            'is'      => 'PC'
        },
        'email' => {
            'is' => 'BE'
        },
        'branchcode' => {
            'is'      => '',
            'content' => 'MPL'
        },
        'surname' => {
            'is' => 'AE'
        }
    },
};
my $patron_hashref_expected = {
    'email'        => 'kyle@kylehall.info',
    'surname'      => 'Kyle M. Hall',
    'branchcode'   => 'MPL',
    'categorycode' => 'ST',
    'cardnumber'   => 'MPL9876543210',
    'userid'       => 'MPL9876543210'
};
my $patron_hashref =
  C4::Auth_with_sip::sip_to_koha_patron( $sip_hashref, $server,
    'MPL9876543210' );
is_deeply( $patron_hashref, $patron_hashref_expected, 'Koha-style patron hashref matches expected patron hashref' );
