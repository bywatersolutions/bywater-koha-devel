package Koha::Checkout;

# Copyright ByWater Solutions 2015
# Copyright 2016 Koha Development Team
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Carp;
use DateTime;

use Koha::Checkouts::ReturnClaims;
use Koha::Database;
use Koha::DateUtils;
use Koha::Items;

use base qw(Koha::Object);

=head1 NAME

Koha::Checkout - Koha Checkout object class

=head1 API

=head2 Class Methods

=cut

=head3 is_overdue

my  $is_overdue = $checkout->is_overdue( [ $reference_dt ] );

Return 1 if the checkout is overdue.

A reference date can be passed, in this case it will be used, otherwise today
will be the reference date.

=cut

sub is_overdue {
    my ( $self, $dt ) = @_;
    $dt ||= DateTime->now( time_zone => C4::Context->tz );
    my $is_overdue =
      DateTime->compare( dt_from_string( $self->date_due, 'sql' ), $dt ) == -1
      ? 1
      : 0;
    return $is_overdue;
}

=head3 item

my $item = $checkout->item;

Return the checked out item

=cut

sub item {
    my ( $self ) = @_;
    my $item_rs = $self->_result->item;
    return Koha::Item->_new_from_dbic( $item_rs );
}

=head3 patron

my $patron = $checkout->patron

Return the patron for who the checkout has been done

=cut

sub patron {
    my ( $self ) = @_;
    my $patron_rs = $self->_result->borrower;
    return Koha::Patron->_new_from_dbic( $patron_rs );
}

=head3 claim_returned

my $return_claim = $checkout->claim_returned();

=cut

sub claim_returned {
    my ( $self, $params ) = @_;

    my $notes           = $params->{notes};
    my $charge_lost_fee = $params->{charge_lost_fee};
    my $created_by      = $params->{created_by};

    $created_by ||= C4::Context->userenv->{number} if C4::Context->userenv;

    my $claim = Koha::Checkouts::ReturnClaims->find( { issue_id => $self->id } );
    $claim ||= Koha::Checkouts::ReturnClaims->find( { old_issue_id => $self->id } );

    $claim ||= Koha::Checkouts::ReturnClaim->new(
        {
            issue_id       => $self->id,
            itemnumber     => $self->itemnumber,
            borrowernumber => $self->borrowernumber,
            notes          => $notes,
            created_on     => dt_from_string,
            created_by     => $created_by,
        }
    )->store();

    my $ClaimReturnedLostValue = C4::Context->preference('ClaimReturnedLostValue');
    C4::Items::ModItem( { itemlost => $ClaimReturnedLostValue }, undef, $self->itemnumber );

    my $ClaimReturnedChargeFee = C4::Context->preference('ClaimReturnedChargeFee');
    $charge_lost_fee =
        $ClaimReturnedChargeFee eq 'charge'    ? 1
      : $ClaimReturnedChargeFee eq 'no_charge' ? 0
      :   $charge_lost_fee;    # $ClaimReturnedChargeFee eq 'ask'
    C4::Circulation::LostItem( $self->itemnumber, 'claim_returned' ) if $charge_lost_fee;

    return $claim;
}

=head3 type

=cut

sub _type {
    return 'Issue';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

Jonathan Druart <jonathan.druart@bugs.koha-community.org>

=cut

1;
