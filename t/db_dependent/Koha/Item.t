#!/usr/bin/perl

# Copyright 2019 Koha Development team
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

use Test::More tests => 3;

use Koha::Items;
use Koha::Database;

use t::lib::TestBuilder;
use t::lib::Mocks;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'hidden_in_opac() tests' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    my $item  = $builder->build_sample_item({ itemlost => 2 });
    my $rules = {};

    # disable hidelostitems as it interteres with OpachiddenItems for the calculation
    t::lib::Mocks::mock_preference( 'hidelostitems', 0 );

    ok( !$item->hidden_in_opac, 'No rules passed, shouldn\'t hide' );
    ok( !$item->hidden_in_opac({ rules => $rules }), 'Empty rules passed, shouldn\'t hide' );

    # enable hidelostitems to verify correct behaviour
    t::lib::Mocks::mock_preference( 'hidelostitems', 1 );
    ok( $item->hidden_in_opac, 'Even with no rules, item should hide because of hidelostitems syspref' );

    # disable hidelostitems
    t::lib::Mocks::mock_preference( 'hidelostitems', 0 );
    my $withdrawn = $item->withdrawn + 1; # make sure this attribute doesn't match

    $rules = { withdrawn => [$withdrawn], itype => [ $item->itype ] };

    ok( $item->hidden_in_opac({ rules => $rules }), 'Rule matching itype passed, should hide' );



    $schema->storage->txn_rollback;
};

subtest 'has_pending_hold() tests' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $dbh = C4::Context->dbh;
    my $item  = $builder->build_sample_item({ itemlost => 0 });
    my $itemnumber = $item->itemnumber;

    $dbh->do("INSERT INTO tmp_holdsqueue (surname,borrowernumber,itemnumber) VALUES ('Clamp',42,$itemnumber)");
    ok( $item->has_pending_hold, "Yes, we have a pending hold");
    $dbh->do("DELETE FROM tmp_holdsqueue WHERE itemnumber=$itemnumber");
    ok( !$item->has_pending_hold, "We don't have a pending hold if nothing in the tmp_holdsqueue");
    
    $schema->storage->txn_rollback;
};

subtest 'renewal_branchcode' => sub {
    plan tests => 13;

    $schema->storage->txn_begin;

    my $item = $builder->build_sample_item();
    my $branch = $builder->build_object({ class => 'Koha::Libraries' });
    my $checkout = $builder->build_object({
        class => 'Koha::Checkouts',
        value => {
            itemnumber => $item->itemnumber,
        }
    });


    C4::Context->interface( 'intranet' );
    t::lib::Mocks::mock_userenv({ branchcode => $branch->branchcode });

    is( $item->renewal_branchcode, $branch->branchcode, "If interface not opac, we get the branch from context");
    is( $item->renewal_branchcode({ branch => "PANDA"}), $branch->branchcode, "If interface not opac, we get the branch from context even if we pass one in");
    C4::Context->set_userenv(51, 'userid4tests', undef, 'firstname', 'surname', undef, undef, 0, undef, undef, undef ); #mock userenv doesn't let us set null branch
    is( $item->renewal_branchcode({ branch => "PANDA"}), "PANDA", "If interface not opac, we get the branch we pass one in if context not set");

    C4::Context->interface( 'opac' );

    t::lib::Mocks::mock_preference('OpacRenewalBranch', undef);
    is( $item->renewal_branchcode, 'OPACRenew', "If interface opac and OpacRenewalBranch undef, we get OPACRenew");
    is( $item->renewal_branchcode({branch=>'COW'}), 'OPACRenew', "If interface opac and OpacRenewalBranch undef, we get OPACRenew even if branch passed");

    t::lib::Mocks::mock_preference('OpacRenewalBranch', 'none');
    is( $item->renewal_branchcode, '', "If interface opac and OpacRenewalBranch is none, we get blank string");
    is( $item->renewal_branchcode({branch=>'COW'}), '', "If interface opac and OpacRenewalBranch is none, we get blank string even if branch passed");

    t::lib::Mocks::mock_preference('OpacRenewalBranch', 'checkoutbranch');
    is( $item->renewal_branchcode, $checkout->branchcode, "If interface opac and OpacRenewalBranch set to checkoutbranch, we get branch of checkout");
    is( $item->renewal_branchcode({branch=>'MONKEY'}), $checkout->branchcode, "If interface opac and OpacRenewalBranch set to checkoutbranch, we get branch of checkout even if branch passed");

    t::lib::Mocks::mock_preference('OpacRenewalBranch','patronhomebranch');
    is( $item->renewal_branchcode, $checkout->patron->branchcode, "If interface opac and OpacRenewalBranch set to patronbranch, we get branch of patron");
    is( $item->renewal_branchcode({branch=>'TURKEY'}), $checkout->patron->branchcode, "If interface opac and OpacRenewalBranch set to patronbranch, we get branch of patron even if branch passed");

    t::lib::Mocks::mock_preference('OpacRenewalBranch','itemhomebranch');
    is( $item->renewal_branchcode, $item->homebranch, "If interface opac and OpacRenewalBranch set to itemhomebranch, we get homebranch of item");
    is( $item->renewal_branchcode({branch=>'MANATEE'}), $item->homebranch, "If interface opac and OpacRenewalBranch set to itemhomebranch, we get homebranch of item even if branch passed");

    $schema->storage->txn_rollback;
};
