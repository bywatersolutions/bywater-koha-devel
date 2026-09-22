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
use Test::More tests => 4;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;
use Koha::SystemMessages;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

my $password = 'thePassword123';

subtest 'list() tests' => sub {

    plan tests => 15;

    $schema->storage->txn_begin;

    Koha::SystemMessages->search->delete;

    my $viewer  = build_librarian('view_system_messages');
    my $manager = build_librarian('manage_system_messages');
    my $nobody  = build_librarian();

    $t->get_ok("//$nobody:$password@/api/v1/system_messages")
        ->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $t->get_ok("//$viewer:$password@/api/v1/system_messages")->status_is(200)->json_is( [] );

    my $uncleared = Koha::SystemMessages->add( { component => 'Notices',      message => 'Notice failed' } );
    my $cleared   = Koha::SystemMessages->add( { component => 'Acquisitions', message => 'EDI failed' } );
    $cleared->clear->discard_changes;

    $t->get_ok("//$viewer:$password@/api/v1/system_messages?_order_by=system_message_id")
        ->status_is(200)
        ->json_is( [ $uncleared->to_api, $cleared->to_api ] );

    $t->get_ok("//$manager:$password@/api/v1/system_messages?_order_by=system_message_id")
        ->status_is(200)
        ->json_is( [ $uncleared->to_api, $cleared->to_api ] );

    $t->get_ok( "//$viewer:$password@/api/v1/system_messages?q=" . '{"cleared_date":null}' )
        ->status_is(200)
        ->json_is( [ $uncleared->to_api ] );

    $schema->storage->txn_rollback;
};

subtest 'clear() tests' => sub {

    plan tests => 11;

    $schema->storage->txn_begin;

    my $viewer  = build_librarian('view_system_messages');
    my $manager = build_librarian('manage_system_messages');

    my $message = Koha::SystemMessages->add( { component => 'Notices', message => 'Notice failed' } );
    my $id      = $message->system_message_id;

    $t->put_ok("//$viewer:$password@/api/v1/system_messages/$id/clear")
        ->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $t->put_ok("//$manager:$password@/api/v1/system_messages/$id/clear")
        ->status_is(200)
        ->json_is( '/system_message_id' => $id )
        ->json_like( '/cleared_date' => qr/^\d{4}-\d{2}-\d{2}T/ );

    ok( $message->get_from_storage->cleared_date, 'cleared_date is stored' );

    my $deleted_id = $builder->build_object( { class => 'Koha::SystemMessages' } )->system_message_id;
    Koha::SystemMessages->find($deleted_id)->delete;

    $t->put_ok("//$manager:$password@/api/v1/system_messages/$deleted_id/clear")
        ->status_is(404)
        ->json_is( '/error' => 'System message not found' );

    $schema->storage->txn_rollback;
};

subtest 'clear_all() tests' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    Koha::SystemMessages->search->delete;

    my $viewer  = build_librarian('view_system_messages');
    my $manager = build_librarian('manage_system_messages');

    my $first   = Koha::SystemMessages->add( { component => 'Notices',      message => 'Notice failed' } );
    my $second  = Koha::SystemMessages->add( { component => 'Acquisitions', message => 'EDI failed' } );
    my $earlier = Koha::SystemMessages->add( { component => 'SIP',          message => 'Login failed' } );
    $earlier->clear->discard_changes;
    my $earlier_cleared_date = $earlier->cleared_date;

    $t->put_ok("//$viewer:$password@/api/v1/system_messages/clear")
        ->status_is(403)
        ->json_is( '/error' => 'Authorization failure. Missing required permission(s).' );

    $t->put_ok("//$manager:$password@/api/v1/system_messages/clear")->status_is(204)->content_is(q{});

    is( Koha::SystemMessages->search( { cleared_date => undef } )->count, 0, 'No uncleared messages left' );
    ok( $first->get_from_storage->cleared_date, 'First message is cleared' );
    is(
        $earlier->get_from_storage->cleared_date, $earlier_cleared_date,
        'Already cleared messages keep their cleared_date'
    );

    $schema->storage->txn_rollback;
};

sub build_librarian {
    my ($permission) = @_;

    my $patron = $builder->build_object( { class => 'Koha::Patrons', value => { flags => 0 } } );
    $patron->set_password( { password => $password, skip_validation => 1 } );
    $builder->build(
        {
            source => 'UserPermission',
            value  => { borrowernumber => $patron->borrowernumber, module_bit => 3, code => $permission }
        }
    ) if $permission;

    return $patron->userid;
}
