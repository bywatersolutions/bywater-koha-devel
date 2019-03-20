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

use CGI qw ( -utf8 );

use Test::More tests => 6;
use Test::MockModule;
use t::lib::Mocks;
use t::lib::TestBuilder;

use Koha::AuthUtils;

BEGIN {
    use_ok('C4::ILSDI::Services');
}

my $schema  = Koha::Database->schema;
my $dbh     = C4::Context->dbh;
my $builder = t::lib::TestBuilder->new;

subtest 'AuthenticatePatron test' => sub {

    plan tests => 14;

    $schema->storage->txn_begin;

    my $plain_password = 'tomasito';

    $builder->build({
        source => 'Borrower',
        value => {
            cardnumber => undef,
        }
    });

    my $borrower = $builder->build({
        source => 'Borrower',
        value  => {
            cardnumber => undef,
            password => Koha::AuthUtils::hash_password( $plain_password )
        }
    });

    my $query = new CGI;
    $query->param( 'username', $borrower->{userid});
    $query->param( 'password', $plain_password);

    my $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{id}, $borrower->{borrowernumber}, "userid and password - Patron authenticated" );
    is( $reply->{code}, undef, "Error code undef");

    $query->param('password','ilsdi-passworD');
    $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{code}, 'PatronNotFound', "userid and wrong password - PatronNotFound" );
    is( $reply->{id}, undef, "id undef");

    $query->param( 'password', $plain_password );
    $query->param( 'username', 'wrong-ilsdi-useriD' );
    $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{code}, 'PatronNotFound', "non-existing userid - PatronNotFound" );
    is( $reply->{id}, undef, "id undef");

    $query->param( 'username', uc( $borrower->{userid} ));
    $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{id}, $borrower->{borrowernumber}, "userid is not case sensitive - Patron authenticated" );
    is( $reply->{code}, undef, "Error code undef");

    $query->param( 'username', $borrower->{cardnumber} );
    $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{id}, $borrower->{borrowernumber}, "cardnumber and password - Patron authenticated" );
    is( $reply->{code}, undef, "Error code undef" );

    $query->param( 'password', 'ilsdi-passworD' );
    $reply = C4::ILSDI::Services::AuthenticatePatron( $query );
    is( $reply->{code}, 'PatronNotFound', "cardnumber and wrong password - PatronNotFount" );
    is( $reply->{id}, undef, "id undef" );

    $query->param( 'username', 'randomcardnumber1234' );
    $query->param( 'password', $plain_password );
    $reply = C4::ILSDI::Services::AuthenticatePatron($query);
    is( $reply->{code}, 'PatronNotFound', "non-existing cardnumer/userid - PatronNotFound" );
    is( $reply->{id}, undef, "id undef");

    $schema->storage->txn_rollback;
};


subtest 'GetPatronInfo/GetBorrowerAttributes test for extended patron attributes' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    $schema->resultset( 'Issue' )->delete_all;
    $schema->resultset( 'Borrower' )->delete_all;
    $schema->resultset( 'BorrowerAttribute' )->delete_all;
    $schema->resultset( 'BorrowerAttributeType' )->delete_all;
    $schema->resultset( 'Category' )->delete_all;
    $schema->resultset( 'Item' )->delete_all; # 'Branch' deps. on this
    $schema->resultset( 'Club' )->delete_all;
    $schema->resultset( 'Branch' )->delete_all;

    # Configure Koha to enable ILS-DI server and extended attributes:
    t::lib::Mocks::mock_preference( 'ILS-DI', 1 );
    t::lib::Mocks::mock_preference( 'ExtendedPatronAttributes', 1 );

    # Set up a library/branch for our user to belong to:
    my $lib = $builder->build( {
        source => 'Branch',
        value => {
            branchcode => 'T_ILSDI',
        }
    } );

    # Create a new category for user to belong to:
    my $cat = $builder->build( {
        source => 'Category',
        value  => {
            category_type                 => 'A',
            BlockExpiredPatronOpacActions => -1,
        }
    } );

    # Create a new attribute type:
    my $attr_type = $builder->build( {
        source => 'BorrowerAttributeType',
        value  => {
            code                      => 'HIDEME',
            opac_display              => 0,
            authorised_value_category => '',
            class                     => '',
        }
    } );
    my $attr_type_visible = $builder->build( {
        source => 'BorrowerAttributeType',
        value  => {
            code                      => 'SHOWME',
            opac_display              => 1,
            authorised_value_category => '',
            class                     => '',
        }
    } );

    # Create a new user:
    my $brwr = $builder->build( {
        source => 'Borrower',
        value  => {
            categorycode => $cat->{'categorycode'},
            branchcode   => $lib->{'branchcode'},
        }
    } );

    # Authorised value:
    my $auth = $builder->build( {
        source => 'AuthorisedValue',
        value  => {
            category => $cat->{'categorycode'}
        }
    } );

    # Set the new attribute for our user:
    my $attr_hidden = $builder->build( {
        source => 'BorrowerAttribute',
        value  => {
            borrowernumber => $brwr->{'borrowernumber'},
            code           => $attr_type->{'code'},
            attribute      => '1337 hidden',
        }
    } );
    my $attr_shown = $builder->build( {
        source => 'BorrowerAttribute',
        value  => {
            borrowernumber => $brwr->{'borrowernumber'},
            code           => $attr_type_visible->{'code'},
            attribute      => '1337 shown',
        }
    } );

    my $fine = $builder->build(
        {
            source => 'Accountline',
            value  => {
                borrowernumber    => $brwr->{borrowernumber},
                accountno         => 1,
                accounttype       => 'xxx',
                amountoutstanding => 10
            }
        }
    );

    # Prepare and send web request for IL-SDI server:
    my $query = new CGI;
    $query->param( 'service', 'GetPatronInfo' );
    $query->param( 'patron_id', $brwr->{'borrowernumber'} );
    $query->param( 'show_attributes', '1' );
    $query->param( 'show_fines', '1' );

    my $reply = C4::ILSDI::Services::GetPatronInfo( $query );

    # Build a structure for comparison:
    my $cmp = {
        category_code     => $attr_type_visible->{'category_code'},
        class             => $attr_type_visible->{'class'},
        code              => $attr_shown->{'code'},
        description       => $attr_type_visible->{'description'},
        display_checkout  => $attr_type_visible->{'display_checkout'},
        value             => $attr_shown->{'attribute'},
        value_description => undef,
    };

    is( $reply->{'charges'}, '10.00',
        'The \'charges\' attribute should be correctly filled (bug 17836)' );

    is( scalar( @{$reply->{fines}->{fine}}), 1, 'There should be only 1 account line');
    is(
        $reply->{fines}->{fine}->[0]->{accountlines_id},
        $fine->{accountlines_id},
        "The accountline should be the correct one"
    );

    # Check results:
    is_deeply( $reply->{'attributes'}, [ $cmp ], 'Test GetPatronInfo - show_attributes parameter' );

    ok( exists $reply->{is_expired}, 'There should be the is_expired information');

    # Cleanup
    $schema->storage->txn_rollback;
};


subtest 'LookupPatron test' => sub {

    plan tests => 9;

    $schema->storage->txn_begin;

    $schema->resultset( 'Issue' )->delete_all;
    $schema->resultset( 'Borrower' )->delete_all;
    $schema->resultset( 'BorrowerAttribute' )->delete_all;
    $schema->resultset( 'BorrowerAttributeType' )->delete_all;
    $schema->resultset( 'Category' )->delete_all;
    $schema->resultset( 'Item' )->delete_all; # 'Branch' deps. on this
    $schema->resultset( 'Branch' )->delete_all;

    my $borrower = $builder->build({
        source => 'Borrower',
    });

    my $query = CGI->new();
    my $bad_result = C4::ILSDI::Services::LookupPatron($query);
    is( $bad_result->{message}, 'PatronNotFound', 'No parameters' );

    $query->delete_all();
    $query->param( 'id', $borrower->{firstname} );
    my $optional_result = C4::ILSDI::Services::LookupPatron($query);
    is(
        $optional_result->{id},
        $borrower->{borrowernumber},
        'Valid Firstname only'
    );

    $query->delete_all();
    $query->param( 'id', 'ThereIsNoWayThatThisCouldPossiblyBeValid' );
    my $bad_optional_result = C4::ILSDI::Services::LookupPatron($query);
    is( $bad_optional_result->{message}, 'PatronNotFound', 'Invalid ID' );

    foreach my $id_type (
        'cardnumber',
        'userid',
        'email',
        'borrowernumber',
        'surname',
        'firstname'
    ) {
        $query->delete_all();
        $query->param( 'id_type', $id_type );
        $query->param( 'id', $borrower->{$id_type} );
        my $result = C4::ILSDI::Services::LookupPatron($query);
        is( $result->{'id'}, $borrower->{borrowernumber}, "Checking $id_type" );
    }

    # Cleanup
    $schema->storage->txn_rollback;
};

subtest 'Holds test' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    t::lib::Mocks::mock_preference( 'AllowHoldsOnDamagedItems', 0 );

    my $patron = $builder->build({
        source => 'Borrower',
    });

    my $biblio = $builder->build({
        source => 'Biblio',
    });

    my $biblioitems = $builder->build({
        source => 'Biblioitem',
        value => {
            biblionumber => $biblio->{biblionumber},
        }
    });

    my $item = $builder->build({
        source => 'Item',
        value => {
            biblionumber => $biblio->{biblionumber},
            damaged => 1
        }
    });

    my $query = new CGI;
    $query->param( 'patron_id', $patron->{borrowernumber});
    $query->param( 'bib_id', $biblio->{biblionumber});

    my $reply = C4::ILSDI::Services::HoldTitle( $query );
    is( $reply->{code}, 'damaged', "Item damaged" );

    my $item_o = Koha::Items->find($item->{itemnumber});
    $item_o->damaged(0)->store;

    my $hold = $builder->build({
        source => 'Reserve',
        value => {
            borrowernumber => $patron->{borrowernumber},
            biblionumber => $biblio->{biblionumber},
            itemnumber => $item->{itemnumber}
        }
    });

    $reply = C4::ILSDI::Services::HoldTitle( $query );
    is( $reply->{code}, 'itemAlreadyOnHold', "Item already on hold" );

    my $biblio_with_no_item = $builder->build({
        source => 'Biblio',
    });

    $query = new CGI;
    $query->param( 'patron_id', $patron->{borrowernumber});
    $query->param( 'bib_id', $biblio_with_no_item->{biblionumber});

    $reply = C4::ILSDI::Services::HoldTitle( $query );
    is( $reply->{code}, 'NoItems', 'Biblio has no item' );

    my $biblio2 = $builder->build({
        source => 'Biblio',
    });

    my $biblioitems2 = $builder->build({
        source => 'Biblioitem',
        value => {
            biblionumber => $biblio2->{biblionumber},
        }
    });

    my $item2 = $builder->build({
        source => 'Item',
        value => {
            biblionumber => $biblio2->{biblionumber},
            damaged => 0
        }
    });

    t::lib::Mocks::mock_preference( 'ReservesControlBranch', 'PatronLibrary' );
    my $issuingrule = $builder->build({
        source => 'Issuingrule',
        value => {
            categorycode => $patron->{categorycode},
            itemtype => $item2->{itype},
            branchcode => $patron->{branchcode},
            reservesallowed => 0,
        }
    });

    $query = new CGI;
    $query->param( 'patron_id', $patron->{borrowernumber});
    $query->param( 'bib_id', $biblio2->{biblionumber});
    $query->param( 'item_id', $item2->{itemnumber});

    $reply = C4::ILSDI::Services::HoldItem( $query );
    is( $reply->{code}, 'tooManyReserves', "Too many reserves" );

    my $biblio3 = $builder->build({
        source => 'Biblio',
    });

    my $biblioitems3 = $builder->build({
        source => 'Biblioitem',
        value => {
            biblionumber => $biblio3->{biblionumber},
        }
    });

    # Adding a holdable item to biblio 3.
    my $item3 = $builder->build({
        source => 'Item',
        value => {
            biblionumber => $biblio3->{biblionumber},
            damaged => 0,
        }
    });

    my $item4 = $builder->build({
        source => 'Item',
        value => {
            biblionumber => $biblio3->{biblionumber},
            damaged => 1,
        }
    });

    my $issuingrule2 = $builder->build({
        source => 'Issuingrule',
        value => {
            categorycode => $patron->{categorycode},
            itemtype => $item3->{itype},
            branchcode => $patron->{branchcode},
            reservesallowed => 10,
        }
    });

    $query = new CGI;
    $query->param( 'patron_id', $patron->{borrowernumber});
    $query->param( 'bib_id', $biblio3->{biblionumber});
    $query->param( 'item_id', $item4->{itemnumber});

    $reply = C4::ILSDI::Services::HoldItem( $query );
    is( $reply->{code}, 'damaged', "Item is damaged" );

    $schema->storage->txn_rollback;
};

subtest 'Holds test for branch transfer limits' => sub {

    plan tests => 4;

    $schema->storage->txn_begin;

    # Test enforement of branch transfer limits
    t::lib::Mocks::mock_preference( 'UseBranchTransferLimits', '1' );
    t::lib::Mocks::mock_preference( 'BranchTransferLimitsType', 'itemtype' );

    my $patron = $builder->build({
        source => 'Borrower',
    });

    my $origin_branch = $builder->build(
        {
            source => 'Branch',
            value  => {
                pickup_location => 1,
            }
        }
    );
    my $pickup_branch = $builder->build(
        {
            source => 'Branch',
            value  => {
                pickup_location => 1,
            }
        }
    );

    my $biblio = $builder->build({
        source => 'Biblio',
    });
    my $biblioitem = $builder->build({
        source => 'Biblioitem',
        value => {
            biblionumber => $biblio->{biblionumber},
        }
    });
    my $item = $builder->build({
        source => 'Item',
        value => {
            homebranch => $origin_branch->{branchcode},
            holdingbranch => $origin_branch->{branchcode},
            biblionumber => $biblio->{biblionumber},
            damaged => 0,
            itemlost => 0,
        }
    });

    Koha::IssuingRules->search()->delete();
    my $issuingrule = $builder->build({
        source => 'Issuingrule',
        value => {
            categorycode => '*',
            itemtype => '*',
            branchcode => '*',
            reservesallowed => 99,
        }
    });

    my $limit = Koha::Item::Transfer::Limit->new({
        toBranch => $pickup_branch->{branchcode},
        fromBranch => $item->{holdingbranch},
        itemtype => $item->{itype},
    })->store();

    my $query = new CGI;
    $query->param( 'pickup_location', $pickup_branch->{branchcode} );
    $query->param( 'patron_id', $patron->{borrowernumber});
    $query->param( 'bib_id', $biblio->{biblionumber});
    $query->param( 'item_id', $item->{itemnumber});

    my $reply = C4::ILSDI::Services::HoldItem( $query );
    is( $reply->{code}, 'cannotBeTransferred', "Item hold, Item cannot be transferred" );

    $reply = C4::ILSDI::Services::HoldTitle( $query );
    is( $reply->{code}, 'cannotBeTransferred', "Record hold, Item cannot be transferred" );

    t::lib::Mocks::mock_preference( 'UseBranchTransferLimits', '0' );

    $reply = C4::ILSDI::Services::HoldItem( $query );
    is( $reply->{code}, undef, "Item hold, Item can be transferred" );

    Koha::Holds->search()->delete();

    $reply = C4::ILSDI::Services::HoldTitle( $query );
    is( $reply->{code}, undef, "Record hold, Item con be transferred" );

    $schema->storage->txn_rollback;
}
