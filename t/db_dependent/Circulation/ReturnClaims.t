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

use Test::More tests => 1;
use Test::MockModule;
use Test::Warn;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Circulation;
use Koha::IssuingRules;
use Koha::Checkouts;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new();

# Mock userenv, used by AddIssue
my $library = $builder->build_object(
    {
        class => 'Koha::Libraries',
    }
);
my $context = Test::MockModule->new('C4::Context');
$context->mock(
    'userenv',
    sub {
        return { branch => $library->id };
    }
);

Koha::IssuingRules->search->delete;
my $rule = Koha::IssuingRule->new(
    {
        categorycode => '*',
        itemtype     => '*',
        branchcode   => '*',
        maxissueqty  => 99,
        issuelength  => 1,
    }
);
$rule->store();

subtest 'Test return claims' => sub {
    plan tests => 15;

    my $itemtype = $builder->build_object(
        {
            class => 'Koha::ItemTypes',
            value => {
                rentalcharge       => 0,
                defaultreplacecost => 0,
                processfee         => 0,
                notforloan         => 0,
            }
        }
    );
    my $biblio = $builder->build_object( { class => 'Koha::Biblios' } );
    my $item = $builder->build_object(
        {
            class => 'Koha::Items',
            value => {
                biblionumber     => $biblio->biblionumber,
                notforloan       => 0,
                itemlost         => 0,
                withdrawn        => 0,
                replacementprice => 23,
                itype            => $itemtype->id,
            }
        }
    );
    my $item2 = $builder->build_object(
        {
            class => 'Koha::Items',
            value => {
                biblionumber     => $biblio->biblionumber,
                notforloan       => 0,
                itemlost         => 0,
                withdrawn        => 0,
                replacementprice => 42,
            }
        }
    );
    my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
    my $issue  = AddIssue( $patron->unblessed, $item->barcode );
    my $issue2 = AddIssue( $patron->unblessed, $item2->barcode );

    my $checkout  = Koha::Checkouts->find( $issue->id );
    my $checkout2 = Koha::Checkouts->find( $issue2->id );

    is( $checkout->itemnumber, $item->itemnumber,
        'First checkout created successfully' );
    is( $checkout2->itemnumber, $item2->itemnumber,
        'Second checkout created successfully' );

    my $claim = $checkout->claim_returned(
        {
            charge => 'charge',
            notes  => 'Test note',
        }
    );
    my $claim2 = $checkout2->claim_returned(
        {
            charge => 'no_charge',
            notes  => 'Test note 2',
        }
    );

    is( $claim->biblio->id, $biblio->id, 'Method "biblio" functions correctly' );
    is( $claim->checkout->id, $checkout->id, 'Method "checkout" functions correctly' );
    is( $claim->item->id, $item->id, 'Method "item" functions correctly' );
    is( $claim->patron->id, $patron->id, 'Method "patron" functions correctly' );

    $item = Koha::Items->find( $item->id );
    $item2 = Koha::Items->find( $item->id );

    is( $item->itemlost, C4::Context->preference('ClaimsReturnedLostAV'), 'First item lost status is set correctly' );
    is( $item2->itemlost, C4::Context->preference('ClaimsReturnedLostAV'), 'Second item lost status is set correctly' );

    $checkout = Koha::Checkouts->find( $checkout->id );
    $checkout2 = Koha::Checkouts->find( $checkout2->id );

    is( $checkout, undef, 'First item is no longer checked out' );
    is( $checkout2, undef, 'Second item is no longer checkout out');

    is( $patron->account->balance, 23, 'Patron was charged correctly' );

    $claim->resolve( { resolution => 'FOUND_IN_LIBRARY' } );

    $claim = Koha::Checkouts::ReturnClaims->find( $claim->id );
    is( $claim->resolution, 'FOUND_IN_LIBRARY', 'Method "resolve" sets resolution correctly' );

    $item = Koha::Items->find( $item->id );
    is( $item->itemlost, 0, 'Item is no longer lost after claim is resolved' );

    my $claims = Koha::Checkouts::ReturnClaims->search( { borrowernumber => $patron->id } );
    is( $claims->count, 2, 'Correctly found two claims for patron' );
    is( $claims->unresolved->count, 1, 'Correctly found one unresolved claim for patron' );
};
