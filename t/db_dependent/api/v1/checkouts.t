#!/usr/bin/env perl

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

use Test::NoWarnings;
use Test::More tests => 117;
use Test::MockModule;
use Test::Mojo;
use t::lib::Mocks;
use t::lib::TestBuilder;

use DateTime;

use C4::Context;
use C4::Circulation qw( AddIssue AddReturn CanBookBeIssued );

use Koha::ActionLogs;
use Koha::CirculationRules;
use Koha::Database;
use Koha::DateUtils qw( dt_from_string output_pref );

use JSON qw( encode_json from_json );

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );
my $t = Test::Mojo->new('Koha::REST::V1');

$schema->storage->txn_begin;

my $dbh = C4::Context->dbh;

my $librarian = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => { flags => 2 }
    }
);
my $password = 'thePassword123';
$librarian->set_password( { password => $password, skip_validation => 1 } );
my $userid = $librarian->userid;

my $patron = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => { flags => 0 }
    }
);
my $unauth_password = 'thePassword000';
$patron->set_password( { password => $unauth_password, skip_validattion => 1 } );
my $unauth_userid = $patron->userid;
my $patron_id     = $patron->borrowernumber;

my $branchcode = $builder->build( { source => 'Branch' } )->{branchcode};

$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id")->status_is(200)->json_is( [] );

my $notexisting_patron_id = $patron_id + 1;
$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$notexisting_patron_id")->status_is(200)->json_is( [] );

my $bookings_librarian = $builder->build_object(
    {
        class => 'Koha::Patrons',
        value => { flags => 0 }     # no additional permissions
    }
);
$builder->build(
    {
        source => 'UserPermission',
        value  => {
            borrowernumber => $bookings_librarian->borrowernumber,
            module_bit     => 1,
            code           => 'manage_bookings',
        },
    }
);
$bookings_librarian->set_password( { password => $password, skip_validation => 1 } );
my $bookings_userid = $bookings_librarian->userid;

$t->get_ok("//$bookings_userid:$password@/api/v1/checkouts?patron_id=$patron_id")
    ->status_is( 200, 'manage_bookings allows checkouts access' )
    ->json_is( [] );

Koha::CirculationRules->set_rules(
    {
        categorycode => undef,
        itemtype     => undef,
        branchcode   => undef,
        rules        => {
            renewalperiod   => 7,
            renewalsallowed => 1,
            issuelength     => 5,
        }
    }
);

my $item1 = $builder->build_sample_item;
my $item2 = $builder->build_sample_item;
my $item3 = $builder->build_sample_item;
my $item4 = $builder->build_sample_item;

my $date_due  = DateTime->now->add( weeks => 2 );
my $issue1    = C4::Circulation::AddIssue( $patron, $item1->barcode, $date_due );
my $date_due1 = Koha::DateUtils::dt_from_string( $issue1->date_due );
my $issue2    = C4::Circulation::AddIssue( $patron, $item2->barcode, $date_due );
my $date_due2 = Koha::DateUtils::dt_from_string( $issue2->date_due );
my $issue3    = C4::Circulation::AddIssue( $librarian, $item3->barcode, $date_due );
my $date_due3 = Koha::DateUtils::dt_from_string( $issue3->date_due );
my $issue4    = C4::Circulation::AddIssue( $patron, $item4->barcode );
C4::Circulation::AddReturn( $item4->barcode, $branchcode );

$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id")
    ->status_is(200)
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item1->itemnumber )
    ->json_is( '/0/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) )
    ->json_is( '/1/patron_id' => $patron_id )
    ->json_is( '/1/item_id'   => $item2->itemnumber )
    ->json_is( '/1/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due2 } ) )
    ->json_hasnt('/2');

# Test checked_in parameter, zero means, the response is same as without it
$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id&checked_in=0")
    ->status_is(200)
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item1->itemnumber )
    ->json_is( '/0/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) )
    ->json_is( '/1/patron_id' => $patron_id )
    ->json_is( '/1/item_id'   => $item2->itemnumber )
    ->json_is( '/1/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due2 } ) )
    ->json_hasnt('/2');

# Test checked_in parameter, one measn, the checked in checkout is in the response too
$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id&checked_in=1")
    ->status_is(200)
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item4->itemnumber )
    ->json_hasnt('/1');

$item4->delete;
$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id&checked_in=1")
    ->status_is(200)
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => undef );

$t->get_ok( "//$unauth_userid:$unauth_password@/api/v1/checkouts/" . $issue3->issue_id )->status_is(403)->json_is(
    {
        error                => "Authorization failure. Missing required permission(s).",
        required_permissions => { circulate => "circulate_remaining_permissions" }
    }
);

$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id")
    ->status_is(200)
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item1->itemnumber )
    ->json_is( '/0/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) )
    ->json_is( '/1/patron_id' => $patron_id )
    ->json_is( '/1/item_id'   => $item2->itemnumber )
    ->json_is( '/1/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due2 } ) )
    ->json_hasnt('/2');

$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id&_per_page=1&_page=1")
    ->status_is(200)
    ->header_is( 'X-Total-Count', '2' )
    ->header_like( 'Link', qr|rel="next"| )
    ->header_like( 'Link', qr|rel="first"| )
    ->header_like( 'Link', qr|rel="last"| )
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item1->itemnumber )
    ->json_is( '/0/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) )
    ->json_hasnt('/1');

$t->get_ok("//$userid:$password@/api/v1/checkouts?patron_id=$patron_id&_per_page=1&_page=2")
    ->status_is(200)
    ->header_is( 'X-Total-Count', '2' )
    ->header_like( 'Link', qr|rel="prev"| )
    ->header_like( 'Link', qr|rel="first"| )
    ->header_like( 'Link', qr|rel="last"| )
    ->json_is( '/0/patron_id' => $patron_id )
    ->json_is( '/0/item_id'   => $item2->itemnumber )
    ->json_is( '/0/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due2 } ) )
    ->json_hasnt('/1');

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue1->issue_id )
    ->status_is(200)
    ->json_is( '/patron_id' => $patron_id )
    ->json_is( '/item_id'   => $item1->itemnumber )
    ->json_is( '/due_date'  => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) )
    ->json_hasnt('/1');

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue1->issue_id )
    ->status_is(200)
    ->json_is( '/due_date' => output_pref( { dateformat => "rfc3339", dt => $date_due1 } ) );

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue2->issue_id )
    ->status_is(200)
    ->json_is( '/due_date' => output_pref( { dateformat => "rfc3339", dt => $date_due2 } ) );

my $expected_datedue =
    $date_due->set_time_zone('local')->add( days => 7 )->set( hour => 23, minute => 59, second => 0 );

$t->post_ok( "//$userid:$password@/api/v1/checkouts/" . $issue1->issue_id . "/renewal" )
    ->status_is(201)
    ->json_is( '/due_date' => output_pref( { dateformat => "rfc3339", dt => $expected_datedue } ) )
    ->header_is( Location => "/api/v1/checkouts/" . $issue1->issue_id . "/renewal" );

my $renewal = $issue1->renewals->last;
is( $renewal->renewal_type, 'Manual', 'Manual renewal recorded' );

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue1->issue_id . "/renewals" )
    ->status_is(200)
    ->json_is( '/0/checkout_id' => $issue1->issue_id )
    ->json_is( '/0/interface'   => 'api' )
    ->json_is( '/0/renewer_id'  => $librarian->borrowernumber );

$t->post_ok( "//$unauth_userid:$unauth_password@/api/v1/checkouts/" . $issue3->issue_id . "/renewal" )
    ->status_is(403)
    ->json_is(
    {
        error                => "Authorization failure. Missing required permission(s).",
        required_permissions => { circulate => "circulate_remaining_permissions" }
    }
    );

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue2->issue_id . "/allows_renewal" )
    ->status_is(200)
    ->json_is(
    {
        allows_renewal   => Mojo::JSON->true,
        max_renewals     => 1,
        unseen_renewals  => 0,
        current_renewals => 0,
        error            => undef
    }
    );

$t->post_ok( "//$userid:$password@/api/v1/checkouts/" . $issue2->issue_id . "/renewal" )
    ->status_is(201)
    ->json_is( '/due_date' => output_pref( { dateformat => "rfc3339", dt => $expected_datedue } ) )
    ->header_is( Location => "/api/v1/checkouts/" . $issue2->issue_id . "/renewal" );

$t->post_ok( "//$userid:$password@/api/v1/checkouts/" . $issue1->issue_id . "/renewal" )
    ->status_is(403)
    ->json_is( { error => 'Renewal not authorized (too_many)', error_code => 'too_many' } );

$t->get_ok( "//$userid:$password@/api/v1/checkouts/" . $issue2->issue_id . "/allows_renewal" )
    ->status_is(200)
    ->json_is(
    {
        allows_renewal   => Mojo::JSON->false,
        max_renewals     => 1,
        unseen_renewals  => 0,
        current_renewals => 1,
        error            => 'too_many'
    }
    );

#Confirm we can get a checkout with a note
$issue1->note("Test")->notedate( dt_from_string() )->store;
$t->get_ok("//$userid:$password@/api/v1/checkouts")->status_is(200);

$schema->storage->txn_rollback;

subtest 'get_availability() tests' => sub {

    plan tests => 59;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $other   = $builder->build_object( { class => 'Koha::Libraries' } );

    # flags => 2: all circulate permissions, force_checkout included
    my $librarian =
        $builder->build_object( { class => 'Koha::Patrons', value => { flags => 2, branchcode => $library->id } } );
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $unprivileged = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $unprivileged->set_password( { password => $password, skip_validation => 1 } );
    my $unprivileged_userid = $unprivileged->userid;

    my $patron    = build_patron();
    my $patron_id = $patron->id;
    my $item      = $builder->build_sample_item;
    my $item_id   = $item->id;

    my ( %impossible, %confirmation, %alerts, %messages, $userenv_library );
    my $mocked_circ = Test::MockModule->new('C4::Circulation');
    $mocked_circ->mock(
        'CanBookBeIssued',
        sub {
            $userenv_library = C4::Context->userenv->{branch};
            return ( {%impossible}, {%confirmation}, {%alerts}, {%messages} );
        }
    );

    my $url = "//$userid:$password@/api/v1/checkouts/availability?item_id=$item_id&patron_id=$patron_id";

    $t->get_ok("//$unprivileged_userid:$password@/api/v1/checkouts/availability?item_id=$item_id&patron_id=$patron_id")
        ->status_is(403);

    # Not found
    my $deleted_item    = $builder->build_sample_item;
    my $deleted_item_id = $deleted_item->id;
    $deleted_item->delete;
    $t->get_ok("//$userid:$password@/api/v1/checkouts/availability?item_id=$deleted_item_id&patron_id=$patron_id")
        ->status_is(404)
        ->json_is( '/error_code' => 'not_found' );

    my $deleted_patron    = build_patron();
    my $deleted_patron_id = $deleted_patron->id;
    $deleted_patron->delete;
    $t->get_ok("//$userid:$password@/api/v1/checkouts/availability?item_id=$item_id&patron_id=$deleted_patron_id")
        ->status_is(404)
        ->json_is( '/error_code' => 'not_found' );

    # Available
    $t->get_ok($url)->status_is(200)->json_is(
        {
            blockers           => {},
            confirms           => {},
            warnings           => {},
            forced             => [],
            confirmation_token => undef,
        }
    );

    # Blocked
    %impossible = ( GNA => 1 );
    $t->get_ok($url)
        ->status_is(200)
        ->json_is( '/blockers'           => { gone_no_address => 1 } )
        ->json_is( '/confirms'           => {} )
        ->json_is( '/confirmation_token' => undef );
    %impossible = ();

    # Warnings
    %alerts   = ( OTHER_CHARGES                    => '5.00' );
    %messages = ( ONSITE_CHECKOUT_WILL_BE_SWITCHED => 1 );
    $t->get_ok($url)
        ->status_is(200)
        ->json_is( '/blockers' => {} )
        ->json_is( '/warnings' => { other_charges => '5.00', onsite_checkout_will_be_switched => 1 } );
    %alerts   = ();
    %messages = ();

    # Needs confirmation
    %confirmation = ( DEBT => '10.00' );
    $t->get_ok($url)->status_is(200)->json_is( '/confirms' => { debt => '10.00' } )->json_has('/confirmation_token');
    my $availability = $item->checkout_availability( { patron => $patron, user => $librarian } );
    ok(
        $availability->check_token( $t->tx->res->json('/confirmation_token') ),
        'Token bound to item, patron and user'
    );
    %confirmation = ();

    # Overrides
    %impossible = ( GNA => 1, DEBARRED => 1 );
    $t->get_ok( $url => { 'x-koha-override' => 'gone_no_address' } )
        ->status_is(200)
        ->json_is( '/blockers' => { patron_debarred => 1 } )
        ->json_is( '/warnings' => { gone_no_address => 1 } )
        ->json_is( '/forced'   => ['gone_no_address'] );

    $t->get_ok( $url => { 'x-koha-override' => 'any' } )
        ->status_is(200)
        ->json_is( '/blockers' => {} )
        ->json_is( '/warnings' => { gone_no_address => 1, patron_debarred => 1 } )
        ->json_is( '/forced'   => [ 'gone_no_address', 'patron_debarred' ] );
    %impossible = ();

    # Unforceable blocker
    %impossible = ( NO_OPEN_DAYS => 1 );
    $t->get_ok( $url => { 'x-koha-override' => 'any' } )
        ->status_is(200)
        ->json_is( '/blockers' => { no_open_days => 1 } )
        ->json_is( '/forced'   => [] );
    %impossible = ();

    # Overrides require force_checkout
    my $circulator        = build_circulator();
    my $circulator_userid = $circulator->userid;
    %impossible = ( GNA => 1 );
    $t->get_ok(
        "//$circulator_userid:$password@/api/v1/checkouts/availability?item_id=$item_id&patron_id=$patron_id" =>
            { 'x-koha-override' => 'any' } )
        ->status_is(200)
        ->json_is( '/blockers' => { gone_no_address => 1 } )
        ->json_is( '/forced'   => [] );
    %impossible = ();

    # Library
    $t->get_ok($url)->status_is(200);
    is( $userenv_library, $library->id, 'The logged in library is used by default' );

    $t->get_ok( $url . '&library_id=' . $other->id )->status_is(200);
    is( $userenv_library, $other->id, 'The library_id parameter is used' );

    my $deleted_library    = $builder->build_object( { class => 'Koha::Libraries' } );
    my $deleted_library_id = $deleted_library->id;
    $deleted_library->delete;
    $t->get_ok( $url . "&library_id=$deleted_library_id" )
        ->status_is(400)
        ->json_is( '/error_code' => 'invalid_parameter_value' );

    t::lib::Mocks::mock_preference( 'IndependentBranches', 1 );
    $t->get_ok( $url . '&library_id=' . $other->id )->status_is(403)->json_is( '/error_code' => 'library_not_allowed' );
    $t->get_ok( $url . '&library_id=' . $library->id )->status_is(200);

    my $superlibrarian =
        $builder->build_object( { class => 'Koha::Patrons', value => { flags => 1, branchcode => $library->id } } );
    $superlibrarian->set_password( { password => $password, skip_validation => 1 } );
    my $superlibrarian_userid = $superlibrarian->userid;
    $t->get_ok(
              "//$superlibrarian_userid:$password@/api/v1/checkouts/availability?item_id=$item_id&patron_id=$patron_id"
            . '&library_id='
            . $other->id )->status_is( 200, 'Superlibrarians can use any library' );
    t::lib::Mocks::mock_preference( 'IndependentBranches', 0 );

    $schema->storage->txn_rollback;
};

subtest 'add() tests' => sub {

    plan tests => 73;

    $schema->storage->txn_begin;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $other   = $builder->build_object( { class => 'Koha::Libraries' } );

    # flags => 2: all circulate permissions, force_checkout included
    my $librarian =
        $builder->build_object( { class => 'Koha::Patrons', value => { flags => 2, branchcode => $library->id } } );
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $unprivileged = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $unprivileged->set_password( { password => $password, skip_validation => 1 } );
    my $unprivileged_userid = $unprivileged->userid;

    my $patron    = build_patron();
    my $patron_id = $patron->id;

    my ( %impossible, %confirmation );
    my $mocked_circ = Test::MockModule->new('C4::Circulation');
    $mocked_circ->mock(
        'CanBookBeIssued',
        sub { return ( {%impossible}, {%confirmation}, {}, {} ); }
    );

    my $add_issue_params;
    my $mocked_controller = Test::MockModule->new('Koha::REST::V1::Checkouts');
    $mocked_controller->mock(
        'AddIssue',
        sub {
            $add_issue_params = $_[6];
            return C4::Circulation::AddIssue(@_);
        }
    );

    my $url = "//$userid:$password@/api/v1/checkouts";

    my $item = $builder->build_sample_item;
    $t->post_ok( "//$unprivileged_userid:$password@/api/v1/checkouts" => json =>
            { item_id => $item->id, patron_id => $patron_id } )->status_is(403);

    # Bad requests
    $t->post_ok( $url => json => { patron_id => $patron_id } )
        ->status_is(400)
        ->json_is( '/error_code' => 'MISSING_OR_WRONG_PARAMETERS' );

    my $other_item = $builder->build_sample_item;
    $t->post_ok(
        $url => json => { item_id => $item->id, external_id => $other_item->barcode, patron_id => $patron_id } )
        ->status_is(409)
        ->json_is( '/error_code' => 'ITEM_ID_NOT_MATCHING_EXTERNAL_ID' );

    # Not found
    my $deleted_item    = $builder->build_sample_item;
    my $deleted_item_id = $deleted_item->id;
    $deleted_item->delete;
    $t->post_ok( $url => json => { item_id => $deleted_item_id, patron_id => $patron_id } )
        ->status_is(404)
        ->json_is( '/error_code' => 'not_found' );

    my $deleted_patron    = build_patron();
    my $deleted_patron_id = $deleted_patron->id;
    $deleted_patron->delete;
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $deleted_patron_id } )
        ->status_is(404)
        ->json_is( '/error_code' => 'not_found' );

    # Checkout
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(201)
        ->json_is( '/item_id'    => $item->id )
        ->json_is( '/patron_id'  => $patron_id )
        ->json_is( '/library_id' => $library->id, 'Checked out at the logged in library' );
    my $checkout_id = $t->tx->res->json('/checkout_id');
    $t->header_is( 'Location' => "/api/v1/checkouts/$checkout_id" );

    $item = $builder->build_sample_item;
    $t->post_ok( $url => json => { external_id => $item->barcode, patron_id => $patron_id } )
        ->status_is(201)
        ->json_is( '/item_id' => $item->id );

    # Library
    $item = $builder->build_sample_item;
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $patron_id, library_id => $other->id } )
        ->status_is(201)
        ->json_is( '/library_id' => $other->id, 'Checked out at the library_id library' );

    $item = $builder->build_sample_item;
    t::lib::Mocks::mock_preference( 'IndependentBranches', 1 );
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $patron_id, library_id => $other->id } )
        ->status_is(403)
        ->json_is( '/error_code' => 'library_not_allowed' );
    t::lib::Mocks::mock_preference( 'IndependentBranches', 0 );
    is( $item->checkout, undef, 'Item not checked out' );

    # Blocked
    $item       = $builder->build_sample_item;
    %impossible = ( GNA => 1 );
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(403)
        ->json_is( '/error_code' => 'checkout_blocked' )
        ->json_is( '/blockers'   => { gone_no_address => 1 } );
    is( $item->checkout, undef, 'Item not checked out' );
    %impossible = ();

    # Confirmation
    %confirmation = ( DEBT => '10.00' );
    $t->post_ok( $url => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(412)
        ->json_is( '/error_code' => 'confirmation_required' )
        ->json_is( '/confirms'   => { debt => '10.00' } )
        ->json_is( '/forced'     => [] )
        ->json_has('/confirmation_token');
    my $token = $t->tx->res->json('/confirmation_token');
    is( $item->checkout, undef, 'Item not checked out' );

    $t->post_ok( "$url?confirmation=wrong" => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(412)
        ->json_is( '/error_code' => 'confirmation_required' );

    # The token is bound to the patron
    my $patron_b = build_patron();
    $t->post_ok( "$url?confirmation=$token" => json => { item_id => $item->id, patron_id => $patron_b->id } )
        ->status_is(412)
        ->json_is( '/error_code' => 'confirmation_required' );
    is( $item->checkout, undef, 'A token for a patron cannot be used for another one' );

    $t->post_ok( "$url?confirmation=$token" => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(201)
        ->json_is( '/patron_id' => $patron_id );
    $t->header_is( 'Location' => '/api/v1/checkouts/' . $t->tx->res->json('/checkout_id') );
    is_deeply( $add_issue_params->{confirmations}, ['DEBT'], 'Confirmations passed to AddIssue' );
    %confirmation = ();

    # Overrides
    $item       = $builder->build_sample_item;
    %impossible = ( GNA => 1 );
    $t->post_ok(
        $url => { 'x-koha-override' => 'gone_no_address' } => json => { item_id => $item->id, patron_id => $patron_id }
    )->status_is(201);
    is_deeply( $add_issue_params->{forced}, ['GNA'], 'Overridden blocker passed to AddIssue as forced' );

    # Overridden blockers along with confirmations
    $item         = $builder->build_sample_item;
    %confirmation = ( DEBT => '10.00' );
    $t->post_ok( $url => { 'x-koha-override' => 'any' } => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(412)
        ->json_is( '/confirms' => { debt => '10.00' } )
        ->json_is( '/forced'   => ['gone_no_address'] );
    $token = $t->tx->res->json('/confirmation_token');
    $t->post_ok( "$url?confirmation=$token" => { 'x-koha-override' => 'any' } => json =>
            { item_id => $item->id, patron_id => $patron_id } )->status_is(201);
    is_deeply( $add_issue_params->{forced},        ['GNA'],  'Overridden blocker passed to AddIssue as forced' );
    is_deeply( $add_issue_params->{confirmations}, ['DEBT'], 'Confirmations passed to AddIssue' );
    %confirmation = ();

    # Overrides require force_checkout
    my $circulator        = build_circulator();
    my $circulator_userid = $circulator->userid;
    $item = $builder->build_sample_item;
    $t->post_ok( "//$circulator_userid:$password@/api/v1/checkouts" => { 'x-koha-override' => 'any' } => json =>
            { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(403)
        ->json_is( '/error_code' => 'checkout_blocked' )
        ->json_is( '/blockers'   => { gone_no_address => 1 } );
    %impossible = ();

    # Unforceable blocker
    %impossible = ( NO_OPEN_DAYS => 1 );
    $t->post_ok( $url => { 'x-koha-override' => 'any' } => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(403)
        ->json_is( '/blockers' => { no_open_days => 1 } );
    is( $item->checkout, undef, 'Item not checked out' );
    %impossible = ();

    $schema->storage->txn_rollback;
};

subtest 'public routes tests' => sub {

    plan tests => 54;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 2 } } );
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $patron = build_patron();
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $patron_id     = $patron->id;
    my $patron_userid = $patron->userid;

    my ( %impossible, %confirmation, %alerts );
    my $mocked_circ = Test::MockModule->new('C4::Circulation');
    $mocked_circ->mock(
        'CanBookBeIssued',
        sub { return ( {%impossible}, {%confirmation}, {%alerts}, {} ); }
    );

    my $item    = $builder->build_sample_item;
    my $item_id = $item->id;

    my $availability_url =
        "//$patron_userid:$password@/api/v1/public/checkouts/availability?item_id=$item_id&patron_id=$patron_id";
    my $checkout_url = "//$patron_userid:$password@/api/v1/public/patrons/$patron_id/checkouts";

    # Availability
    $t->get_ok("/api/v1/public/checkouts/availability?item_id=$item_id&patron_id=$patron_id")->status_is(401);
    $t->get_ok("//$userid:$password@/api/v1/public/checkouts/availability?item_id=$item_id&patron_id=$patron_id")
        ->status_is(403);

    $t->get_ok($availability_url)
        ->status_is(200)
        ->json_is( '/blockers' => {} )
        ->json_is( '/confirms' => {} )
        ->json_is( '/warnings' => {} )
        ->json_has('/confirmation_token')
        ->json_hasnt('/forced');

    # Confirmations are promoted to blockers, other patrons' data is removed
    %impossible   = ( WTHDRAWN          => 1 );
    %confirmation = ( ISSUED_TO_ANOTHER => 1, issued_borrowernumber => $librarian->id, RENEW_ISSUE => 1 );
    %alerts       = ( OTHER_CHARGES     => '5.00' );
    $t->get_ok($availability_url)
        ->status_is(200)
        ->json_is( '/blockers' => { WTHDRAWN      => 1, ISSUED_TO_ANOTHER => 1 } )
        ->json_is( '/confirms' => { RENEW_ISSUE   => 1 } )
        ->json_is( '/warnings' => { OTHER_CHARGES => '5.00' } );
    %impossible   = ();
    %confirmation = ();
    %alerts       = ();

    # Hold confirmations are gated by AllowItemsOnHoldCheckoutSCO
    %confirmation = ( RESERVED => 1, RESERVE_WAITING => 1, TRANSFERRED => 1, PROCESSING => 1 );

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 0 );
    $t->get_ok($availability_url)->status_is(200)->json_is(
        '/blockers' => {
            RESERVED        => 1,
            RESERVE_WAITING => 1,
            TRANSFERRED     => 1,
            PROCESSING      => 1
        }
    )->json_is( '/confirms' => {} );

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 1 );
    $t->get_ok($availability_url)
        ->status_is(200)
        ->json_is( '/blockers' => { RESERVE_WAITING => 1, TRANSFERRED => 1, PROCESSING => 1 } )
        ->json_is( '/confirms' => {} );

    t::lib::Mocks::mock_preference( 'AllowItemsOnHoldCheckoutSCO', 2 );
    $t->get_ok($availability_url)->status_is(200)->json_is( '/blockers' => {} )->json_is( '/confirms' => {} );
    %confirmation = ();

    my $deleted_item    = $builder->build_sample_item;
    my $deleted_item_id = $deleted_item->id;
    $deleted_item->delete;

    # Checkout
    t::lib::Mocks::mock_preference( 'OpacTrustedCheckout', 0 );
    $t->post_ok( "/api/v1/public/patrons/$patron_id/checkouts" => json => { item_id => $item_id } )
        ->status_is(401)
        ->json_is( { error => "Authentication failure." } );
    $t->post_ok( $checkout_url => json => { item_id => $item_id, patron_id => $patron_id } )
        ->status_is(405)
        ->json_is( { error => "Feature disabled", error_code => "FEATURE_DISABLED" } );

    t::lib::Mocks::mock_preference( 'OpacTrustedCheckout', 1 );
    $t->post_ok( "//$userid:$password@/api/v1/public/patrons/$patron_id/checkouts" => json =>
            { item_id => $item_id, patron_id => $patron_id } )
        ->status_is(403)
        ->json_is( { error => "Unprivileged user cannot access another user's resources" } );

    $t->post_ok( $checkout_url => json => { item_id => $deleted_item_id, patron_id => $patron_id } )
        ->status_is(409)
        ->json_is( '/error_code' => 'ITEM_NOT_FOUND' );

    %impossible = ( WTHDRAWN => 1 );
    $t->post_ok( $checkout_url => json => { item_id => $item_id, patron_id => $patron_id } )
        ->status_is(403)
        ->json_is( { error => "Checkout not authorized (WTHDRAWN)" } );
    %impossible = ();

    %confirmation = ( RENEW_ISSUE => 1 );
    $t->post_ok( $checkout_url => json => { item_id => $item_id, patron_id => $patron_id } )
        ->status_is(412)
        ->json_is( { error => "Confirmation error" } );

    $t->get_ok($availability_url)->status_is(200);
    my $token = $t->tx->res->json('/confirmation_token');
    $t->post_ok( "$checkout_url?confirmation=$token" => json => { item_id => $item_id, patron_id => $patron_id } )
        ->status_is(201)
        ->json_is( '/item_id' => $item_id );
    %confirmation = ();

    $item = $builder->build_sample_item;
    $t->post_ok( $checkout_url => json => { item_id => $item->id, patron_id => $patron_id } )
        ->status_is(201)
        ->json_is( '/patron_id' => $patron_id );

    $schema->storage->txn_rollback;
};

subtest 'renew with fine override (x-koha-override: debt_limit)' => sub {
    plan tests => 15;

    $schema->storage->txn_begin;

    # Create a librarian with circulate permission
    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2 }     # Superlibrarian
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    # Create a regular patron
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );

    # Create a branch and set up userenv
    my $branch = $builder->build( { source => 'Branch' } );
    t::lib::Mocks::mock_userenv(
        { branchcode => $branch->{branchcode}, borrowernumber => $librarian->borrowernumber } );

    # Set up circulation rules
    Koha::CirculationRules->set_rules(
        {
            categorycode => undef,
            itemtype     => undef,
            branchcode   => undef,
            rules        => {
                renewalperiod   => 7,
                renewalsallowed => 10,
                issuelength     => 5,
            }
        }
    );

    my $item = $builder->build_sample_item;

    # Check out the item
    my $checkout = AddIssue( $patron, $item->barcode );

    # Set FineNoRenewals to a low amount
    t::lib::Mocks::mock_preference( 'FineNoRenewals', 5 );

    # Add a fine that exceeds the limit
    my $account = Koha::Account->new( { patron_id => $patron->borrowernumber } );
    $account->add_debit(
        {
            amount      => 10.00,
            type        => 'OVERDUE',
            interface   => 'test',
            description => 'Test fine',
            item_id     => $item->itemnumber,
        }
    );

    my $checkout_id = $checkout->id;

    # Test 1: Renewal should be blocked due to excessive fines
    $t->post_ok("//$userid:$password@/api/v1/checkouts/$checkout_id/renewal")
        ->status_is(403)
        ->json_like( '/error' => qr/too_much_owing/ );

    # Test 2: Override should fail when AllowFineOverrideRenewing is disabled
    t::lib::Mocks::mock_preference( 'AllowFineOverrideRenewing', 0 );

    $t->post_ok( "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => { 'x-koha-override' => 'debt_limit' } )
        ->status_is(403)
        ->json_like( '/error' => qr/too_much_owing/ );

    # Test 3: Override should succeed when AllowFineOverrideRenewing is enabled
    t::lib::Mocks::mock_preference( 'AllowFineOverrideRenewing', 1 );

    $t->post_ok( "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => { 'x-koha-override' => 'debt_limit' } )
        ->status_is(201)
        ->json_has('/due_date');

    # Refresh checkout
    $checkout = Koha::Checkouts->find($checkout_id);

    # Test 4: Test with /renewals endpoint (alternative endpoint)
    # Add another checkout to test the other endpoint
    my $item2        = $builder->build_sample_item;
    my $checkout2    = AddIssue( $patron, $item2->barcode );
    my $checkout2_id = $checkout2->id;

    # Should be blocked without override
    $t->post_ok("//$userid:$password@/api/v1/checkouts/$checkout2_id/renewals")
        ->status_is(403)
        ->json_like( '/error' => qr/too_much_owing/ );

    # Should succeed with override
    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout2_id/renewals" => { 'x-koha-override' => 'debt_limit' } )
        ->status_is(201)
        ->json_has('/due_date');

    $schema->storage->txn_rollback;
};

subtest 'list checkouts that have been checked in and the patron has been deleted' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    # Create a librarian with circulate permission
    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2 }     # Superlibrarian
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    # Create a regular patron
    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    my $patron_id = $patron->borrowernumber;

    my $old_checkout = $builder->build_object(
        {
            class => 'Koha::Old::Checkouts',
            value => { borrowernumber => $patron_id }
        }
    );
    my $old_checkout_id = encode_json( { checkout_id => $old_checkout->id } );

    # Test 1: Checkout should be returned
    $t->get_ok("//$userid:$password@/api/v1/checkouts?checked_in=1&q=$old_checkout_id")
        ->status_is(200)
        ->json_is( '/0/patron_id' => $patron_id );

    my $old_checkout_2 = $builder->build_object(
        {
            class => 'Koha::Old::Checkouts',
            value => { borrowernumber => undef }
        }
    );
    my $old_checkout_2_id = encode_json( { checkout_id => $old_checkout_2->id } );

    # Test 2: Checkout should be returned with null patron_id

    $t->get_ok("//$userid:$password@/api/v1/checkouts?checked_in=1&q=$old_checkout_2_id")
        ->status_is(200)
        ->json_is( '/0/patron_id' => undef );

    $schema->storage->txn_rollback;
};

subtest 'renew() with requested due_date and bookings' => sub {
    plan tests => 21;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'AllowRenewalLimitOverride', 1 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2 }     # circulate
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );
    my $patron2 = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item    = $builder->build_sample_item( { library => $library->branchcode, bookable => 1 } );

    Koha::CirculationRules->set_rules(
        {
            branchcode   => $library->branchcode,
            categorycode => $patron->categorycode,
            itemtype     => $item->effective_itemtype,
            rules        => {
                renewalsallowed => 1,
                renewalperiod   => 7,
                issuelength     => 7,
            }
        }
    );

    my $start_date = dt_from_string()->truncate( to => 'minute' );
    my $end_date   = $start_date->clone->add( days => 7 );

    my $booking = $builder->build_object(
        {
            class => 'Koha::Bookings',
            value => {
                patron_id         => $patron->borrowernumber,
                item_id           => $item->itemnumber,
                biblio_id         => $item->biblio->biblionumber,
                pickup_library_id => $library->branchcode,
                start_date        => $start_date,
                end_date          => $end_date,
                status            => 'new',
            }
        }
    );

    t::lib::Mocks::mock_userenv( { branchcode => $library->branchcode } );
    my $checkout = AddIssue( $patron, $item->barcode, $end_date->clone );
    is( $checkout->booking_id, $booking->booking_id, 'Checkout linked to the booking at issue' );
    my $checkout_id = $checkout->issue_id;

    # Renewal with a requested due date syncs the booking end_date
    my $renewal_due = $end_date->clone->add( days => 3 );
    $t->post_ok( "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => json =>
            { due_date => output_pref( { dateformat => 'rfc3339', dt => $renewal_due } ) } )
        ->status_is(201)
        ->json_is( '/due_date' => output_pref( { dateformat => 'rfc3339', dt => $renewal_due } ) );

    $booking->discard_changes;
    is(
        dt_from_string( $booking->end_date )->compare($renewal_due), 0,
        'Booking end_date synced to the renewed due date'
    );

    # Renewal count limit reached; renewal_limit override required
    my $second_renewal_due = $end_date->clone->add( days => 5 );
    $t->post_ok( "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => json =>
            { due_date => output_pref( { dateformat => 'rfc3339', dt => $second_renewal_due } ) } )
        ->status_is(403)
        ->json_is( '/error_code' => 'too_many' );

    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => { 'x-koha-override' => 'renewal_limit' } =>
            json => { due_date => output_pref( { dateformat => 'rfc3339', dt => $second_renewal_due } ) } )
        ->status_is(201)
        ->json_is( '/due_date' => output_pref( { dateformat => 'rfc3339', dt => $second_renewal_due } ) );

    $booking->discard_changes;
    is(
        dt_from_string( $booking->end_date )->compare($second_renewal_due), 0,
        'Booking end_date follows the overridden renewal'
    );

    # A requested due date running into the next booking is refused
    my $next_booking = $builder->build_object(
        {
            class => 'Koha::Bookings',
            value => {
                patron_id         => $patron2->borrowernumber,
                item_id           => $item->itemnumber,
                biblio_id         => $item->biblio->biblionumber,
                pickup_library_id => $library->branchcode,
                start_date        => $second_renewal_due->clone->add( days => 3 ),
                end_date          => $second_renewal_due->clone->add( days => 7 ),
                status            => 'new',
            }
        }
    );

    my $clashing_due = $second_renewal_due->clone->add( days => 4 );
    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => { 'x-koha-override' => 'renewal_limit' } =>
            json => { due_date => output_pref( { dateformat => 'rfc3339', dt => $clashing_due } ) } )
        ->status_is(403)
        ->json_is( '/error_code' => 'booked' );

    $booking->discard_changes;
    $checkout->discard_changes;
    is(
        dt_from_string( $booking->end_date )->compare($second_renewal_due), 0,
        'Booking end_date unchanged after refused renewal'
    );
    is(
        dt_from_string( $checkout->date_due )->compare($second_renewal_due), 0,
        'Checkout due date unchanged after refused renewal'
    );

    # The newer plural endpoint accepts due_date too (same controller)
    my $plural_renewal_due = $second_renewal_due->clone->add( days => 1 );
    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout_id/renewals" => { 'x-koha-override' => 'renewal_limit' } =>
            json => { due_date => output_pref( { dateformat => 'rfc3339', dt => $plural_renewal_due } ) } )
        ->status_is(201)
        ->json_is( '/due_date' => output_pref( { dateformat => 'rfc3339', dt => $plural_renewal_due } ) );

    $booking->discard_changes;
    is(
        dt_from_string( $booking->end_date )->compare($plural_renewal_due), 0,
        'Booking end_date synced by a renewal through the plural endpoint'
    );

    $schema->storage->txn_rollback;
};

subtest 'renew() records the renewal_limit override in the action log' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'AllowRenewalLimitOverride', 1 );
    t::lib::Mocks::mock_preference( 'RenewalLog',                1 );

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2 }     # circulate
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item    = $builder->build_sample_item( { library => $library->branchcode } );

    Koha::CirculationRules->set_rules(
        {
            branchcode   => $library->branchcode,
            categorycode => $patron->categorycode,
            itemtype     => $item->effective_itemtype,
            rules        => {
                renewalsallowed => 5,
                renewalperiod   => 7,
                issuelength     => 7,
            }
        }
    );

    t::lib::Mocks::mock_userenv( { branchcode => $library->branchcode } );
    my $checkout_id = AddIssue( $patron, $item->barcode )->issue_id;

    my $last_renewal_confirmations = sub {
        my $log = Koha::ActionLogs->search(
            { module   => 'CIRCULATION', action => 'RENEWAL', object => $patron->borrowernumber },
            { order_by => { -desc => 'action_id' } }
        )->next;
        return from_json( $log->info )->{confirmations};
    };

    $t->post_ok("//$userid:$password@/api/v1/checkouts/$checkout_id/renewal")->status_is(201);
    ok(
        !grep( { $_ eq 'RENEWAL_LIMIT' } @{ $last_renewal_confirmations->() } ),
        'No RENEWAL_LIMIT without the override'
    );

    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => { 'x-koha-override' => 'renewal_limit' } )
        ->status_is(201);
    ok(
        grep( { $_ eq 'RENEWAL_LIMIT' } @{ $last_renewal_confirmations->() } ),
        'RENEWAL_LIMIT logged with the override'
    );

    $schema->storage->txn_rollback;
};

subtest 'renew() with a malformed requested due_date' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $librarian = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 2 }     # circulate
        }
    );
    my $password = 'thePassword123';
    $librarian->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $librarian->userid;

    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $patron  = $builder->build_object( { class => 'Koha::Patrons' } );
    my $item    = $builder->build_sample_item( { library => $library->branchcode } );

    Koha::CirculationRules->set_rules(
        {
            branchcode   => $library->branchcode,
            categorycode => $patron->categorycode,
            itemtype     => $item->effective_itemtype,
            rules        => {
                renewalsallowed => 1,
                renewalperiod   => 7,
                issuelength     => 7,
            }
        }
    );

    t::lib::Mocks::mock_userenv( { branchcode => $library->branchcode } );
    my $checkout     = AddIssue( $patron, $item->barcode );
    my $checkout_id  = $checkout->issue_id;
    my $original_due = $checkout->date_due;

    $t->post_ok(
        "//$userid:$password@/api/v1/checkouts/$checkout_id/renewal" => json => { due_date => '2026-03-15T10:00:00' }
        )    # Missing the mandatory RFC3339 offset/Z
        ->status_is(400)->json_is( '/error_code' => 'invalid_parameter_value' );

    $checkout->discard_changes;
    is( $checkout->date_due, $original_due, 'Checkout due date unchanged after a rejected due_date' );

    $schema->storage->txn_rollback;
};

sub build_patron {
    my $category = $builder->build_object( { class => 'Koha::Patron::Categories', value => { category_type => 'A' } } );
    return $builder->build_object(
        { class => 'Koha::Patrons', value => { flags => 0, categorycode => $category->id } } );
}

sub build_circulator {

    # circulate_remaining_permissions only, no force_checkout
    my $circulator = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $circulator->id,
                module_bit     => 1,
                code           => 'circulate_remaining_permissions',
            },
        }
    );
    $circulator->set_password( { password => $password, skip_validation => 1 } );
    return $circulator;
}
