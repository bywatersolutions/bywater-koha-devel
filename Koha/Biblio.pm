package Koha::Biblio;

# Copyright ByWater Solutions 2014
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

use base qw(Koha::Object);

use C4::Circulation qw(GetIssuingRule);
use Koha::Items;
use Koha::ArticleRequests;
use Koha::ArticleRequest::Status;

=head1 NAME

Koha::Biblio - Koha Biblio Object class

=head1 API

=head2 Class Methods

=cut

=head3 can_article_request

my $bool = $biblio->can_article_request( $borrower );

Returns true if article requests can be made for this record

$borrower must be a Koha::Borrower object

=cut

sub can_article_request {
    my ( $self, $borrower ) = @_;

    my $rule = $self->article_request_type($borrower);
    return q{} if $rule eq 'item_only' && !$self->items()->count();
    return 1 if $rule && $rule ne 'no';

    return q{};
}

=head3 article_request_type

my $type = $biblio->article_request_type( $borrower );

Returns the article request type based on items, or on the record
itself if there are no items.

$borrower must be a Koha::Borrower object

=cut

sub article_request_type {
    my ( $self, $borrower ) = @_;

    my $rule = $self->article_request_type_for_items( $borrower );
    return $rule if $rule;

    # If the record has no items that are requestable, go by the record itemtype
    $rule = $self->article_request_type_for_bib($borrower);
    return $rule if $rule;

    return q{};
}

=head3 article_request_type_for_bib

my $type = $biblio->article_request_type_for_bib

Returns the article request type 'yes', 'no', 'item_only', 'bib_only', for the given record

=cut

sub article_request_type_for_bib {
    my ( $self, $borrower ) = @_;

    my $borrowertype = $borrower->categorycode;
    my $itemtype     = $self->itemtype();
    my $rules        = GetIssuingRule( $borrowertype, $itemtype );

    return $rules->{article_requests} || q{};
}

=head3 article_request_type_for_items

my $type = $biblio->article_request_type_for_items

Returns the article request type 'yes', 'no', 'item_only', 'bib_only', for the given record's items

If there is a conflict where some items are 'bib_only' and some are 'item_only', 'bib_only' will be returned.

=cut

sub article_request_type_for_items {
    my ( $self, $borrower ) = @_;

    my $counts;
    foreach my $item ( $self->items()->as_list() ) {
        my $rule = $item->article_request_type($borrower);
        return $rule if $rule eq 'bib_only';    # we don't need to go any further
        $counts->{$rule}++;
    }

    return 'item_only' if $counts->{item_only};
    return 'yes'       if $counts->{yes};
    return 'no'        if $counts->{no};
    return q{};
}

=head3 article_requests

my @requests = $biblio->article_requests

Returns the article requests associated with this Biblio

=cut

sub article_requests {
    my ( $self, $borrower ) = @_;

    $self->{_article_requests} ||= Koha::ArticleRequests->search( { biblionumber => $self->biblionumber() } );

    return wantarray ? $self->{_article_requests}->as_list : $self->{_article_requests};
}

=head3 article_requests_current

my @requests = $biblio->article_requests_current

Returns the article requests associated with this Biblio that are incomplete

=cut

sub article_requests_current {
    my ( $self, $borrower ) = @_;

    $self->{_article_requests_current} ||= Koha::ArticleRequests->search(
        {
            biblionumber => $self->biblionumber(),
            -or          => [
                { status => Koha::ArticleRequest::Status::Open },
                { status => Koha::ArticleRequest::Status::Processing }
            ]
        }
    );

    return wantarray ? $self->{_article_requests_current}->as_list : $self->{_article_requests_current};
}

=head3 article_requests_finished

my @requests = $biblio->article_requests_finished

Returns the article requests associated with this Biblio that are completed

=cut

sub article_requests_finished {
    my ( $self, $borrower ) = @_;

    $self->{_article_requests_finished} ||= Koha::ArticleRequests->search(
        {
            biblionumber => $self->biblionumber(),
            -or          => [
                { status => Koha::ArticleRequest::Status::Completed },
                { status => Koha::ArticleRequest::Status::Canceled }
            ]
        }
    );

    return wantarray ? $self->{_article_requests_finished}->as_list : $self->{_article_requests_finished};
}

=head3 items

my @items = $biblio->items();
my $items = $biblio->items();

Returns a list of Koha::Item objects or a Koha::Items object of
items associated with this bib

=cut

sub items {
    my ( $self ) = @_;

    $self->{_items} ||= Koha::Items->search({ biblionumber => $self->biblionumber() });

    return $self->{_items};
}

=head3 type

=cut

sub type {
    return 'Biblio';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
