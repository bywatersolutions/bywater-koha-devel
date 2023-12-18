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

use t::lib::Mocks;
use t::lib::TestBuilder;

BEGIN {
    use_ok('Koha::Library::FloatLimit');
    use_ok('Koha::Library::FloatLimits');
}

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder  = t::lib::TestBuilder->new;
my $library1 = $builder->build( { source => 'Branch' } );
my $library2 = $builder->build( { source => 'Branch' } );
my $library3 = $builder->build( { source => 'Branch' } );
my $itemtype = $builder->build_object( { class => 'Koha::ItemTypes' } );

my $biblio = $builder->build_sample_biblio();

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
say "C4::Circulation::IsBranchTransferAllowed( $to, $from, $code )";

subtest 'onloan items excluded from ratio calculation' => sub {
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
};

subtest 'items in transit counted toward destination branch' => sub {
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

    # Test 5: Library2's physical count should still be 10
    my $library2_physical = Koha::Items->search(
        {
            holdingbranch => $library2->{branchcode},
            itype         => $itemtype->itemtype,
            onloan        => undef
        }
    )->count;

    is( $library2_physical, 10, "Library2 still has 10 physical items" );

    # Library2's count should now be 10 + 2 = 12
    is(
        Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} )->branchcode,
        $library3->{branchcode},
        "Library3 still selected after items in transit to library2"
    );
};

$schema->storage->txn_rollback;
