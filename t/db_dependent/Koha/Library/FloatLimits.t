#!/usr/bin/perl

# Copyright 2023 ByWater Solutions
#
# This file is part of Koha
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
use C4::Circulation qw(CreateBranchTransferLimit);
use Koha::DateUtils qw( dt_from_string );
use Koha::Library::FloatLimit;
use Koha::Library::FloatLimits;

use t::lib::Mocks;
use t::lib::TestBuilder;

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder  = t::lib::TestBuilder->new;
my $library1 = $builder->build( { source => 'Branch' } );
my $library2 = $builder->build( { source => 'Branch' } );
my $library3 = $builder->build( { source => 'Branch' } );
my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

my $biblio = $builder->build_sample_biblio();

# Create initial items for testing
for ( 1 .. 5 ) {
    $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $library1->{branchcode},
            holdingbranch => $library1->{branchcode},
            itype         => $itemtype->itemtype,
        }
    );
}

for ( 1 .. 10 ) {
    $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $library2->{branchcode},
            holdingbranch => $library2->{branchcode},
            itype         => $itemtype->itemtype,
        }
    );
}

for ( 1 .. 15 ) {
    $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $library3->{branchcode},
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
        }
    );
}

my $item = $builder->build_sample_item(
    {
        biblionumber  => $biblio->biblionumber,
        homebranch    => $library1->{branchcode},
        holdingbranch => $library1->{branchcode},
        itype         => $itemtype->itemtype,
    }
);

my $limit1 = Koha::Library::FloatLimit->new(
    {
        branchcode  => $library1->{branchcode},
        itemtype    => $itemtype->itemtype,
        float_limit => 1,
    }
)->store();

my $float_limit2 = Koha::Library::FloatLimit->new(
    {
        branchcode  => $library2->{branchcode},
        itemtype    => $itemtype->itemtype,
        float_limit => 100,
    }
)->store();

my $float_limit3 = Koha::Library::FloatLimit->new(
    {
        branchcode  => $library3->{branchcode},
        itemtype    => $itemtype->itemtype,
        float_limit => 1000,
    }
)->store();

is(
    Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
    $library3->{branchcode},
    "Correct library selected for float limit transfer"
);

t::lib::Mocks::mock_preference( 'UseBranchTransferLimits',  '1' );
t::lib::Mocks::mock_preference( 'BranchTransferLimitsType', 'itemtype' );

my $to   = $library3->{branchcode};
my $from = $item->holdingbranch;
my $code = $itemtype->itemtype;
CreateBranchTransferLimit( $to, $from, $code );

is( C4::Circulation::IsBranchTransferAllowed( $to, $from, $code ), 0, "Transfer to best library is no longer allowed" );

subtest 'FloatLimits: General tests' => sub {
    $schema->storage->txn_begin;
    plan tests => 2;

    # Test with no float limits defined
    my $no_limits_item = $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $library1->{branchcode},
            holdingbranch => $library1->{branchcode},
            itype         => $builder->build_object( { class => 'Koha::ItemTypes' } )->itemtype,
        }
    );

    my $no_limits_result = Koha::Library::FloatLimits->lowest_ratio_library( $no_limits_item, $library1->{branchcode} );
    is( $no_limits_result, undef, "Returns undef when no float limits defined" );

    # Test with only zero float limits
    my $zero_lib      = $builder->build( { source => 'Branch' } );
    my $zero_itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    Koha::Library::FloatLimit->new(
        {
            branchcode  => $zero_lib->{branchcode},
            itemtype    => $zero_itemtype->itemtype,
            float_limit => 0,                          # Zero limit should be excluded
        }
    )->store();

    # Test with item type not in any float limits
    my $unknown_itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );
    my $unknown_item     = $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $library1->{branchcode},
            holdingbranch => $library1->{branchcode},
            itype         => $unknown_itemtype->itemtype,
        }
    );

    my $unknown_result = Koha::Library::FloatLimits->lowest_ratio_library( $unknown_item, $library1->{branchcode} );
    is( $unknown_result, undef, "Returns undef for item type not in float limits" );

    $schema->storage->txn_rollback;

};

subtest 'FloatLimits: Count on loan items against total' => sub {
    $schema->storage->txn_begin;
    plan tests => 5;

    # Reset transfer limits for clean test
    t::lib::Mocks::mock_preference( 'UseBranchTransferLimits', '0' );

    # Verify initial item counts
    my $library2_initial = Koha::Items->search(
        {
            holdingbranch => $library2->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    my $library3_initial = Koha::Items->search(
        {
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    is( $library2_initial, 10, "Library2 initially has 10 available items" );
    is( $library3_initial, 15, "Library3 initially has 15 available items" );

    # Initial library selection based on ratios
    is(
        Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
        $library3->{branchcode},
        "Library3 initially selected (lowest ratio: 15/1000 = 0.015)"
    );

    # Check out enough items from library3 to change the selection
    my @library3_items = Koha::Items->search(
        {
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->as_list;

    my $checkout_date = dt_from_string();
    for my $i ( 0 .. 9 ) {
        $library3_items[$i]->onloan($checkout_date)->store;
    }

    # Verify the count decreased
    my $library3_after_checkout = Koha::Items->search(
        {
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    is( $library3_after_checkout, 5, "Library3 now has 5 available items after 10 checkouts" );

    # Library3 should still be selected
    is(
        Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
        $library3->{branchcode},
        "Library3 still selected after checkouts (ratio now 5/1000 = 0.005, still better than library2's 10/100 = 0.1)"
    );
    $schema->storage->txn_rollback;
};

subtest 'FloatLimits: Count in transit TO items against total' => sub {
    $schema->storage->txn_begin;
    plan tests => 6;

    # Reset transfer limits for clean test
    t::lib::Mocks::mock_preference( 'UseBranchTransferLimits', '0' );

    Koha::Items->search(
        {
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => { '!=' => undef }
        }
    )->update( { onloan => undef } );

    # Verify initial counts
    my $library2_initial = Koha::Items->search(
        {
            holdingbranch => $library2->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    my $library3_initial = Koha::Items->search(
        {
            holdingbranch => $library3->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    is( $library2_initial, 10, "Library2 initially has 10 available items" );
    is( $library3_initial, 15, "Library3 initially has 15 available items" );

    # Initial selection should be library3
    is(
        Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
        $library3->{branchcode},
        "Library3 initially selected (ratio: 15/1000 = 0.015)"
    );

    # Create items in transit TO library2
    my @transit_items;
    for ( 1 .. 2 ) {
        my $transit_item = $builder->build_sample_item(
            {
                biblionumber  => $biblio->biblionumber,
                homebranch    => $library1->{branchcode},
                holdingbranch => $library1->{branchcode},
                itype         => $itemtype->itemtype,
            }
        );
        push @transit_items, $transit_item;
    }

    # Create active transfers to library2
    my $transfer_date = dt_from_string();
    for my $transit_item (@transit_items) {
        Koha::Item::Transfer->new(
            {
                itemnumber    => $transit_item->itemnumber,
                frombranch    => $library1->{branchcode},
                tobranch      => $library2->{branchcode},
                daterequested => $transfer_date,
                datesent      => $transfer_date,
                reason        => 'LibraryFloatLimit'
            }
        )->store;
    }

    # Verify that items in transit are counted toward destination
    my $in_transit_count = Koha::Items->search(
        {
            itype => $itemtype->itemtype,
        },
        {
            join  => 'branchtransfers',
            where => {
                'branchtransfers.tobranch'      => $library2->{branchcode},
                'branchtransfers.datearrived'   => undef,
                'branchtransfers.datecancelled' => undef,
            },
            distinct => 1
        }
    )->count;

    is( $in_transit_count, 2, "2 items are in transit to library2" );

    my $library2_physical = Koha::Items->search(
        {
            holdingbranch => $library2->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    is( $library2_physical, 10, "Library2 still has 10 physical items" );

    is(
        Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
        $library3->{branchcode},
        "Library3 still selected after items in transit to library2"
    );

    $schema->storage->txn_rollback;

};

subtest 'FloatLimits: Do not count in transit FROM items against total' => sub {
    $schema->storage->txn_begin;
    plan tests => 2;

    # Reset transfer limits
    t::lib::Mocks::mock_preference( 'UseBranchTransferLimits', '0' );

    # Create unique itemtype for this test
    my $transit_itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

    # Create test libraries
    my $from_lib = $builder->build( { source => 'Branch' } );
    my $to_lib   = $builder->build( { source => 'Branch' } );

    # Create items at from_lib
    my @from_items;
    for ( 1 .. 8 ) {
        my $from_item = $builder->build_sample_item(
            {
                biblionumber  => $biblio->biblionumber,
                homebranch    => $from_lib->{branchcode},
                holdingbranch => $from_lib->{branchcode},
                itype         => $transit_itemtype->itemtype,    # Use unique itemtype
            }
        );
        push @from_items, $from_item;
    }

    # Create items at to_lib
    for ( 1 .. 5 ) {
        $builder->build_sample_item(
            {
                biblionumber  => $biblio->biblionumber,
                homebranch    => $to_lib->{branchcode},
                holdingbranch => $to_lib->{branchcode},
                itype         => $transit_itemtype->itemtype,    # Use unique itemtype
            }
        );
    }

    # Set float limits
    Koha::Library::FloatLimit->new(
        {
            branchcode  => $from_lib->{branchcode},
            itemtype    => $transit_itemtype->itemtype,    # Use unique itemtype
            float_limit => 10,
        }
    )->store();

    Koha::Library::FloatLimit->new(
        {
            branchcode  => $to_lib->{branchcode},
            itemtype    => $transit_itemtype->itemtype,    # Use unique itemtype
            float_limit => 10,
        }
    )->store();

    # Create test item with unique itemtype
    my $transit_item = $builder->build_sample_item(
        {
            biblionumber  => $biblio->biblionumber,
            homebranch    => $from_lib->{branchcode},
            holdingbranch => $from_lib->{branchcode},
            itype         => $transit_itemtype->itemtype,
        }
    );

    # Initial state: from_lib has 8 items, to_lib has 5 items
    # Ratios: from_lib = 8/10 = 0.8, to_lib = 5/10 = 0.5
    my $initial_result = Koha::Library::FloatLimits->lowest_ratio_library( $transit_item, $from_lib->{branchcode} );
    is( $initial_result->branchcode, $to_lib->{branchcode}, "to_lib selected initially (better ratio)" );

    # Create transfers FROM from_lib TO to_lib (3 items)
    my $transfer_date = dt_from_string();
    for my $i ( 0 .. 2 ) {
        Koha::Item::Transfer->new(
            {
                itemnumber    => $from_items[$i]->itemnumber,
                frombranch    => $from_lib->{branchcode},
                tobranch      => $to_lib->{branchcode},
                daterequested => $transfer_date,
                datesent      => $transfer_date,
                reason        => 'LibraryFloatLimit'
            }
        )->store;
    }

    # After transfers:
    # from_lib effective count = 8 - 3 = 5 (ratio = 5/10 = 0.5)
    # to_lib effective count = 5 + 3 = 8 (ratio = 8/10 = 0.8)
    # Now from_lib should be better choice
    my $after_transfer_result =
        Koha::Library::FloatLimits->lowest_ratio_library( $transit_item, $to_lib->{branchcode} );
    is(
        $after_transfer_result->branchcode, $from_lib->{branchcode},
        "from_lib selected after transfers (items subtracted)"
    );

    $schema->storage->txn_rollback;

};

$schema->storage->txn_rollback;
