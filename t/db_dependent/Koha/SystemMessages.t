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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 3;
use Test::Exception;

use Koha::Database;
use Koha::DateUtils qw( dt_from_string );
use Koha::SystemMessages;

use t::lib::TestBuilder;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'add() tests' => sub {

    plan tests => 15;

    $schema->storage->txn_begin;

    Koha::SystemMessages->search->delete;

    my $message = Koha::SystemMessages->add( { component => 'Notices', message => 'Something failed' } );
    is( ref($message),         'Koha::SystemMessage', 'add() returns a Koha::SystemMessage' );
    is( $message->occurrences, 1,                     'First occurrence' );
    ok( $message->created_date, 'created_date is set' );
    ok( $message->updated_date, 'updated_date is set' );
    is( $message->cleared_date,              undef, 'New message is not cleared' );
    is( Koha::SystemMessages->search->count, 1,     'One row added' );

    $message->set( { updated_date => dt_from_string->subtract( days => 1 ) } )->store;

    my $repeat = Koha::SystemMessages->add( { component => 'Notices', message => 'Something failed' } );
    is( $repeat->system_message_id, $message->system_message_id, 'Same message reuses the uncleared row' );
    is( $repeat->occurrences,       2,                           'occurrences is bumped' );
    ok(
        dt_from_string( $repeat->updated_date ) > dt_from_string->subtract( hours => 1 ),
        'updated_date is moved to now'
    );
    is( Koha::SystemMessages->search->count, 1, 'Still one row' );

    my $other = Koha::SystemMessages->add( { component => 'Acquisitions', message => 'Something failed' } );
    isnt( $other->system_message_id, $message->system_message_id, 'Different component adds a new row' );

    $message->clear;
    my $after_clear = Koha::SystemMessages->add( { component => 'Notices', message => 'Something failed' } );
    isnt( $after_clear->system_message_id, $message->system_message_id, 'A cleared message is not reused' );
    is( $after_clear->occurrences, 1, 'New row starts at one occurrence' );

    throws_ok { Koha::SystemMessages->add( { message => 'Something failed' } ) }
    'Koha::Exceptions::MissingParameter', 'component is mandatory';
    throws_ok { Koha::SystemMessages->add( { component => 'Notices' } ) }
    'Koha::Exceptions::MissingParameter', 'message is mandatory';

    $schema->storage->txn_rollback;
};

subtest 'clear() tests' => sub {

    plan tests => 3;

    $schema->storage->txn_begin;

    my $message = $builder->build_object( { class => 'Koha::SystemMessages', value => { cleared_date => undef } } );

    my $result = $message->clear;
    is( $result->system_message_id, $message->system_message_id, 'clear() returns the message' );
    ok( $message->get_from_storage->cleared_date, 'cleared_date is stored' );
    ok(
        dt_from_string( $message->cleared_date ) > dt_from_string->subtract( hours => 1 ),
        'cleared_date is now'
    );

    $schema->storage->txn_rollback;
};
