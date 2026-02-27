#!/usr/bin/perl

# Copyright 2025 Aleisha Amohia <aleisha@catalyst.net.nz>
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

use Test::More tests => 3;
use Test::Exception;

use Test::NoWarnings;

use t::lib::TestBuilder;

use Koha::Database;
use Koha::OAI::Set;
use Koha::OAI::Sets;
use Koha::OAI::Set::Biblio;
use Koha::OAI::Set::Biblios;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

$schema->storage->txn_begin;

subtest 'Koha::OAI::Set(s) tests' => sub {
    plan tests => 5;

    my $nb_of_sets = Koha::OAI::Sets->search->count;
    my $new_set    = Koha::OAI::Set->new(
        {
            spec => 'test_spec',
            name => 'Test Set',
        }
    )->store;

    ok( $new_set->id, 'New set should have an ID' );
    is( Koha::OAI::Sets->search->count, $nb_of_sets + 1, 'One set should have been added' );

    my $retrieved_set = Koha::OAI::Sets->find( $new_set->id );
    is( $retrieved_set->name, 'Test Set', 'Retrieved set name should match' );

    $retrieved_set->name('Updated Name')->store;
    is( Koha::OAI::Sets->find( $new_set->id )->name, 'Updated Name', 'Set name should be updated' );

    $retrieved_set->delete;
    is( Koha::OAI::Sets->search->count, $nb_of_sets, 'Set should have been deleted' );
};

subtest 'Koha::OAI::Set::Biblio(s) tests' => sub {
    plan tests => 4;

    my $new_set = Koha::OAI::Set->new(
        {
            spec => 'test_spec_biblio',
            name => 'Test Set Biblio',
        }
    )->store;

    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );

    my $new_set_biblio = Koha::OAI::Set::Biblio->new(
        {
            set_id       => $new_set->id,
            biblionumber => $biblio->biblionumber,
        }
    )->store;

    ok( $new_set_biblio, 'New set biblio object created' );

    my $retrieved_set_biblio = Koha::OAI::Set::Biblios->find(
        {
            set_id       => $new_set->id,
            biblionumber => $biblio->biblionumber
        }
    );
    ok( $retrieved_set_biblio, 'Retrieved set biblio object' );

    $retrieved_set_biblio->delete;
    ok(
        !Koha::OAI::Set::Biblios->find(
            {
                set_id       => $new_set->id,
                biblionumber => $biblio->biblionumber
            }
        ),
        'Set biblio should have been deleted'
    );

    $new_set->delete;
    ok( !Koha::OAI::Sets->find( $new_set->id ), 'Set should have been deleted' );
};

$schema->storage->txn_rollback;

1;
