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

use Test::More tests => 5;

use Koha::Database;
use C4::Circulation qw(CreateBranchTransferLimit);

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
    Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} ), $library3->{branchcode},
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

is(
    Koha::Library::FloatLimits->lowest_ratio_library( $item, $library1->{branchcode} ), $library2->{branchcode},
    "Correct library selected for float limit transfer when best cannot be used"
);

$schema->storage->txn_rollback;
