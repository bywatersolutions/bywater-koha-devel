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

use Test::More tests => 6;

use Koha::Database;

use t::lib::TestBuilder;
use t::lib::Mocks;

BEGIN {
    use_ok('Koha::Biblio::Volume');
    use_ok('Koha::Biblio::Volumes');
}

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

t::lib::Mocks::mock_preference('EnableVolumes', 1);

subtest 'Test Koha::Biblio::volumes' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_sample_biblio();

    my @volumes = $biblio->volumes->as_list;
    is( scalar(@volumes), 0, 'Got zero volumes');

    my $volume_1 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();

    @volumes = $biblio->volumes->as_list;
    is( scalar(@volumes), 1, 'Got one volume');
    is( $volumes[0]->id, $volume_1->id, 'Got correct volume');

    my $volume_2 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();

    @volumes = $biblio->volumes->as_list;
    is( scalar(@volumes), 2, 'Got two volumes');
    is( $volumes[0]->id, $volume_1->id, 'Got correct volume 1');
    is( $volumes[1]->id, $volume_2->id, 'Got correct volume 2');

    $schema->storage->txn_rollback;
};

subtest 'Test Koha::Biblio::Volume::add_item & Koha::Biblio::Volume::items' => sub {

    plan tests => 6;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_sample_biblio();
    my $item_1 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    my $item_2 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });

    my $volume = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();

    my $items = $volume->items;
    is( $items->count, 0, 'Volume has no items');

    $volume->add_item({ item_id => $item_1->id });
    my @items = $volume->items->as_list;
    is( scalar(@items), 1, 'Volume has one item');
    is( $items[0]->id, $item_1->id, 'Item 1 is correct' );

    $volume->add_item({ item_id => $item_2->id });
    @items = $volume->items->as_list;
    is( scalar(@items), 2, 'Volume has two items');
    is( $items[0]->id, $item_1->id, 'Item 1 is correct' );
    is( $items[1]->id, $item_2->id, 'Item 2 is correct' );

    $schema->storage->txn_rollback;
};

subtest 'Test Koha::Item::volume' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_sample_biblio();
    my $item_1 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    my $item_2 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });

    is( $item_1->volume, undef, 'Item 1 has no volume');
    is( $item_2->volume, undef, 'Item 2 has no volume');

    my $volume_1 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();
    my $volume_2 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();

    $volume_1->add_item({ item_id => $item_1->id });
    $volume_2->add_item({ item_id => $item_2->id });

    is( $item_1->volume->id, $volume_1->id, 'Got volume 1 correctly' );
    is( $item_2->volume->id, $volume_2->id, 'Got volume 2 correctly' );

    $schema->storage->txn_rollback;
};

subtest 'Koha::Item::delete should delete volume if no other items are using the volume' => sub {

    plan tests => 11;

    $schema->storage->txn_begin;

    my $biblio = $builder->build_sample_biblio();
    my $item_1 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    my $item_2 = $builder->build_sample_item({ biblionumber => $biblio->biblionumber });
    is( $biblio->items->count, 2, 'Bib has 2 items');

    is( $item_1->volume, undef, 'Item 1 has no volume');
    is( $item_2->volume, undef, 'Item 2 has no volume');

    my $volume_1 = Koha::Biblio::Volume->new( { biblionumber => $biblio->id } )->store();

    $volume_1->add_item({ item_id => $item_1->id });
    $volume_1->add_item({ item_id => $item_2->id });

    my $volume = Koha::Biblio::Volumes->find( $volume_1->id );
    is( $volume->id, $volume_1->id, 'Found the correct volume');

    is( $item_1->volume->id, $volume_1->id, 'Item 1 has correct volume');
    is( $item_2->volume->id, $volume_1->id, 'Item 2 has correct volume');

    $item_1->delete();
    is( $biblio->items->count, 1, 'Bib has 2 item');
    $volume = Koha::Biblio::Volumes->find( $volume_1->id );
    is( $volume->id, $volume_1->id, 'Volume still exists after deleting and item, but other items remain');

    is( $item_2->volume->id, $volume_1->id, 'Item 2 still has correct volume');

    $item_2->delete();
    is( $biblio->items->count, 0, 'Bib has 0 items');
    $volume = Koha::Biblio::Volumes->find( $volume_1->id );
    is( $volume, undef, 'Volume was deleted when last item was deleted');

    $schema->storage->txn_rollback;
};
