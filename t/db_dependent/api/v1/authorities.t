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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use utf8;
use Encode;

use Test::More tests => 2;
use Test::MockModule;
use Test::Mojo;
use Test::Warn;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Auth;

use Koha::Authorities;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

my $t = Test::Mojo->new('Koha::REST::V1');

subtest 'get() tests' => sub {

    plan tests => 20;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    $patron->discard_changes;
    my $userid = $patron->userid;

    my $authority = $builder->build_object({ 'class' => 'Koha::Authorities', value => {
      marcxml => q|<?xml version="1.0" encoding="UTF-8"?>
<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">
    <controlfield tag="001">1001</controlfield>
    <datafield tag="110" ind1=" " ind2=" ">
        <subfield code="9">102</subfield>
        <subfield code="a">My Corporation</subfield>
    </datafield>
</record>|
    } });

    $t->get_ok("//$userid:$password@/api/v1/authorities/" . $authority->authid)
      ->status_is(403);

    $patron->flags(4)->store;

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                => { Accept => 'application/weird+format' } )
      ->status_is(400);

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'application/json' } )
      ->status_is(200)
      ->json_is( '/authid', $authority->authid )
      ->json_is( '/authtypecode', $authority->authtypecode );

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'application/marcxml+xml' } )
      ->status_is(200);

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'application/marc-in-json' } )
      ->status_is(200);

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'application/marc' } )
      ->status_is(200);

    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'text/plain' } )
      ->status_is(200)
      ->content_is(q|LDR 00079     2200049   4500
001     1001
110    _9102
       _aMy Corporation|);

    $authority->delete;
    $t->get_ok( "//$userid:$password@/api/v1/authorities/" . $authority->authid
                 => { Accept => 'application/marc' } )
      ->status_is(404)
      ->json_is( '/error', 'Object not found.' );

    $schema->storage->txn_rollback;
};

subtest 'delete() tests' => sub {

    plan tests => 7;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 } # no permissions
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    my $authority = $builder->build_object({ 'class' => 'Koha::Authorities', value => {
      marcxml => q|<?xml version="1.0" encoding="UTF-8"?>
<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd">
    <controlfield tag="001">1001</controlfield>
    <datafield tag="110" ind1=" " ind2=" ">
        <subfield code="9">102</subfield>
        <subfield code="a">My Corporation</subfield>
    </datafield>
</record>|
    } });

    $t->delete_ok("//$userid:$password@/api/v1/authorities/".$authority->authid)
      ->status_is(403, 'Not enough permissions makes it return the right code');

    # Add permissions
    $patron->flags( 2 ** 14 )->store; # 14 => editauthorities userflag

    $t->delete_ok("//$userid:$password@/api/v1/authorities/".$authority->authid)
      ->status_is(204, 'SWAGGER3.2.4')
      ->content_is('', 'SWAGGER3.3.4');

    $t->delete_ok("//$userid:$password@/api/v1/authorities/".$authority->authid)
      ->status_is(404);

    $schema->storage->txn_rollback;
};