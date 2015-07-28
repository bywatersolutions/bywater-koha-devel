package Koha::ArticleRequest;

# Copyright ByWater Solutions 2015
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

use Koha::Database;
use Koha::Borrowers;
use Koha::Biblios;
use Koha::Items;
use Koha::ArticleRequest::Status;

use base qw(Koha::Object);

=head1 NAME

Koha::ArticleRequest - Koha Article Request Object class

=head1 API

=head2 Class Methods

=cut

=head3 process

=cut

sub process {
    my ( $self ) = @_;

    $self->status( Koha::ArticleRequest::Status::Processing );
    return $self->store();
}

=head3 complete

=cut

sub complete {
    my ( $self ) = @_;

    $self->status( Koha::ArticleRequest::Status::Completed );
    return $self->store();
}

=head3 cancel

=cut

sub cancel {
    my ( $self, $notes ) = @_;

    $self->status( Koha::ArticleRequest::Status::Canceled );
    $self->notes( $notes ) if $notes;
    return $self->store();
}


=head3 biblio

Returns the Koha::Biblio object for this article request

=cut

sub biblio {
    my ( $self ) = @_;

    $self->{_biblio} ||= Koha::Biblios->find( $self->biblionumber() );

    return $self->{_biblio};
}

=head3 item

Returns the Koha::Item object for this article request

=cut

sub item {
    my ( $self ) = @_;

    $self->{_item} ||= Koha::Items->find( $self->itemnumber() );

    return $self->{_item};
}

=head3 borrower

Returns the Koha::Borrower object for this article request

=cut

sub borrower {
    my ( $self ) = @_;

    $self->{_borrower} ||= Koha::Borrowers->find( $self->borrowernumber() );

    return $self->{_borrower};
}

=head3 type

=cut

sub type {
    return 'ArticleRequest';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
