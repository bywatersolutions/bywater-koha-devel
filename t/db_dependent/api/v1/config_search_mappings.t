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
use Test::More tests => 5;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;

use YAML::XS;

use Koha::Database;
use Koha::SearchFields;
use Koha::SearchMarcMaps;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );

subtest 'authorization' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $authorized_patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    $builder->build(
        {
            source => 'UserPermission',
            value  => {
                borrowernumber => $authorized_patron->borrowernumber,
                module_bit     => 3,
                code           => 'manage_search_engine_config',
            },
        }
    );
    my $password = 'thePassword123';
    $authorized_patron->set_password( { password => $password, skip_validation => 1 } );

    my $unauthorized_patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 0 }
        }
    );
    $unauthorized_patron->set_password( { password => $password, skip_validation => 1 } );

    $t->get_ok( "//" . $unauthorized_patron->userid . ":$password@/api/v1/config/search_mappings" )->status_is(403);

    $t->get_ok( "//" . $authorized_patron->userid . ":$password@/api/v1/config/search_mappings" )->status_is(200);

    $schema->storage->txn_rollback;
};

subtest 'get JSON (default)' => sub {

    plan tests => 10;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3**2 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    # Clear existing data
    Koha::SearchFields->search->delete;
    Koha::SearchMarcMaps->search->delete;
    $schema->resultset('SearchMarcToField')->search->delete;

    # Create test mapping
    my $search_field = Koha::SearchFields->find_or_create(
        {
            name         => 'title',
            label        => 'Title',
            type         => 'string',
            weight       => 17,
            staff_client => 0,
            opac         => 1,
            mandatory    => 1,
        },
        { key => 'name' }
    );

    my $marc_map = Koha::SearchMarcMaps->find_or_create(
        {
            index_name => 'biblios',
            marc_type  => 'marc21',
            marc_field => '245',
        }
    );

    $search_field->add_to_search_marc_maps(
        $marc_map,
        {
            facet       => 0,
            suggestible => 0,
            sort        => 1,
            filter      => '',
        }
    );

    $t->get_ok("//$userid:$password@/api/v1/config/search_mappings")
        ->status_is(200)
        ->content_type_like(qr/json/)
        ->json_has('/biblios/title')
        ->json_is( '/biblios/title/label'     => 'Title' )
        ->json_is( '/biblios/title/type'      => 'string' )
        ->json_is( '/biblios/title/mandatory' => 1 )
        ->json_is( '/biblios/title/opac'      => 1 );

    my $mapping = $t->tx->res->json->{biblios}{title}{mappings}[0];
    is( $mapping->{marc_field}, '245',    'marc_field is 245' );
    is( $mapping->{marc_type},  'marc21', 'marc_type is marc21' );

    $schema->storage->txn_rollback;
};

subtest 'get YAML' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3**2 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    # Clear existing data
    Koha::SearchFields->search->delete;
    Koha::SearchMarcMaps->search->delete;
    $schema->resultset('SearchMarcToField')->search->delete;

    # Create test mapping
    my $search_field = Koha::SearchFields->find_or_create(
        {
            name         => 'author',
            label        => 'Author',
            type         => 'string',
            staff_client => 1,
            opac         => 1,
            mandatory    => 0,
        },
        { key => 'name' }
    );

    my $marc_map = Koha::SearchMarcMaps->find_or_create(
        {
            index_name => 'biblios',
            marc_type  => 'marc21',
            marc_field => '100a',
        }
    );

    $search_field->add_to_search_marc_maps(
        $marc_map,
        {
            facet       => 1,
            suggestible => 0,
            sort        => 0,
            filter      => '',
        }
    );

    $t->get_ok( "//$userid:$password@/api/v1/config/search_mappings" => { Accept => 'application/yaml' } )
        ->status_is(200)
        ->content_type_like(qr/yaml/);

    my $body     = $t->tx->res->text;
    my $mappings = YAML::XS::Load($body);

    is( ref $mappings->{biblios}{author},                      'HASH',   'YAML contains author field' );
    is( $mappings->{biblios}{author}{label},                   'Author', 'YAML label is correct' );
    is( $mappings->{biblios}{author}{mappings}[0]{marc_field}, '100a',   'YAML marc_field is correct' );

    $schema->storage->txn_rollback;
};

subtest 'type filter' => sub {

    plan tests => 8;

    $schema->storage->txn_begin;

    my $patron = $builder->build_object(
        {
            class => 'Koha::Patrons',
            value => { flags => 3**2 }
        }
    );
    my $password = 'thePassword123';
    $patron->set_password( { password => $password, skip_validation => 1 } );
    my $userid = $patron->userid;

    # Clear existing data
    Koha::SearchFields->search->delete;
    Koha::SearchMarcMaps->search->delete;
    $schema->resultset('SearchMarcToField')->search->delete;

    # Create test field with both marc21 and unimarc mappings
    my $search_field = Koha::SearchFields->find_or_create(
        {
            name         => 'title',
            label        => 'Title',
            type         => 'string',
            staff_client => 1,
            opac         => 1,
            mandatory    => 0,
        },
        { key => 'name' }
    );

    my $marc21_map = Koha::SearchMarcMaps->find_or_create(
        {
            index_name => 'biblios',
            marc_type  => 'marc21',
            marc_field => '245',
        }
    );

    $search_field->add_to_search_marc_maps(
        $marc21_map,
        {
            facet       => 0,
            suggestible => 0,
            sort        => 0,
            filter      => '',
        }
    );

    my $unimarc_map = Koha::SearchMarcMaps->find_or_create(
        {
            index_name => 'biblios',
            marc_type  => 'unimarc',
            marc_field => '200a',
        }
    );

    $search_field->add_to_search_marc_maps(
        $unimarc_map,
        {
            facet       => 0,
            suggestible => 1,
            sort        => 0,
            filter      => '',
        }
    );

    # No filter — both mappings returned
    $t->get_ok("//$userid:$password@/api/v1/config/search_mappings")->status_is(200);

    my $all_mappings = $t->tx->res->json->{biblios}{title}{mappings};
    is( scalar @$all_mappings, 2, 'Unfiltered returns both marc21 and unimarc mappings' );

    # Filter by marc21
    $t->get_ok("//$userid:$password@/api/v1/config/search_mappings?type=marc21")->status_is(200);

    my $marc21_mappings = $t->tx->res->json->{biblios}{title}{mappings};
    is( scalar @$marc21_mappings,          1,        'Filtered to marc21 returns 1 mapping' );
    is( $marc21_mappings->[0]{marc_type},  'marc21', 'Returned mapping is marc21' );
    is( $marc21_mappings->[0]{marc_field}, '245',    'Returned mapping field is 245' );

    $schema->storage->txn_rollback;
};
