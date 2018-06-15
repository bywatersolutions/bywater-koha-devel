package Koha::Checkouts::ReturnClaim;

# Copyright ByWater Solutions 2018
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

use base qw(Koha::Object);

use C4::Circulation qw(_FixAccountForLostAndReturned);
use C4::Context;
use Koha::Biblios;
use Koha::Items;
use Koha::Old::Checkouts;
use Koha::Patrons;
use Koha::RefundLostItemFeeRules;

=head1 NAME

Koha::ReturnClaim - Koha ReturnClaim object class

=head1 API

=head2 Class Methods

=cut

=head3 resolve

  $claim->resolve( { resolution => $resolution_av_value } );

=cut

sub resolve {
    my ( $self, $params ) = @_;

    my $resolution = $params->{resolution};

    return $self unless $resolution;

    my $item = $self->item;
    if (
        Koha::RefundLostItemFeeRules->should_refund(
            {
                current_branch      => C4::Context->userenv->{branch},
                item_home_branch    => $item->homebranch,
                item_holding_branch => $item->holdingbranch,
            }
        )
      )
    {
        C4::Circulation::_FixAccountForLostAndReturned( $self->itemnumber, $self->borrowernumber, $item->barcode );
    }

    $self->resolution($resolution);
    $self->store();

    C4::Items::ModItem( { itemlost => 0 }, undef, $self->itemnumber );

    return $self;
}

=head3 biblio

    my $biblio = $claim->biblio;

=cut

sub biblio {
    my ( $self ) = @_;
    return scalar Koha::Biblios->find( $self->biblionumber );
}

=head3 checkout

    my $checkout = $claim->checkout;

=cut

sub checkout {
    my ( $self ) = @_;

    return scalar Koha::Old::Checkouts->find( $self->issue_id );
}

=head3 item

    my $item = $claim->item;

=cut

sub item {
    my ( $self ) = @_;
    return scalar Koha::Items->find( $self->itemnumber );
}

=head3 patron

    my $patron = $claim->patron;

=cut

sub patron {
    my ( $self ) = @_;
    return scalar Koha::Patrons->find( $self->borrowernumber );
}

=head3 _type

=cut

sub _type {
    return 'ReturnClaim';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
