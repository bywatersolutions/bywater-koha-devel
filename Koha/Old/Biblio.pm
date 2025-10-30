package Koha::Old::Biblio;

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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use base qw(Koha::Object);

use Koha::Database;
use Koha::Biblio;
use Koha::Biblioitem;
use Koha::Biblio::Metadata;
use Koha::Old::Biblio::Metadatas;
use Koha::Old::Biblioitems;
use Koha::SearchEngine::Indexer;

=head1 NAME

Koha::Old::Biblio - Koha Old::Biblio Object class

=head1 API

=head2 Class methods

=cut

=head3 metadata

my $metadata = $deleted_biblio->metadata();

Returns a Koha::Biblio::Metadata object

=cut

sub metadata {
    my ($self) = @_;

    my $metadata = $self->_result->metadata;
    return Koha::Old::Biblio::Metadata->_new_from_dbic($metadata);
}

=head3 record

my $record = $deleted_biblio->record();

Returns a Marc::Record object

=cut

sub record {
    my ($self) = @_;

    return $self->metadata->record;
}

=head3 record_schema

my $schema = $deleted_biblio->record_schema();

Returns the record schema (MARC21, USMARC or UNIMARC).

=cut

sub record_schema {
    my ($self) = @_;

    return $self->metadata->schema // C4::Context->preference("marcflavour");
}

=head3 biblioitem

my $field = $self->biblioitem

Returns the related Koha::Old::Biblioitem object for this Biblio object

=cut

sub biblioitem {
    my ($self) = @_;
    return Koha::Old::Biblioitems->find( { biblionumber => $self->biblionumber } );
}

=head3 to_api

    my $json = $deleted_biblio->to_api;

Overloaded method that returns a JSON representation of the Koha::Old::Biblio object,
suitable for API output. The related Koha::Old::Biblioitem object is merged as expected
on the API.

=cut

sub to_api {
    my ( $self, $args ) = @_;

    my $response = $self->SUPER::to_api($args);

    $args = defined $args ? {%$args} : {};
    delete $args->{embed};

    my $biblioitem = $self->biblioitem->to_api($args);

    return { %$response, %$biblioitem };
}

=head3 to_api_mapping

This method returns the mapping for representing a Koha::Old::Biblio object
on the API.

=cut

sub to_api_mapping {
    return {
        biblionumber  => 'biblio_id',
        frameworkcode => 'framework_id',
        unititle      => 'uniform_title',
        seriestitle   => 'series_title',
        copyrightdate => 'copyright_date',
        datecreated   => 'creation_date',
        timestamp     => 'deleted_on',
    };
}

=head3 restore

    my $biblio = $deleted_biblio->restore;

Restores the deleted biblio record back to the biblio table along with
its biblioitems and metadata. This removes the record from the deleted tables
and re-inserts it into the active tables. The biblio record will be reindexed
after restoration.

Returns the newly restored Koha::Biblio object.

=cut

sub restore {
    my ($self) = @_;

    my $biblio_data     = $self->unblessed;
    my $biblioitem      = $self->biblioitem;
    my $biblioitem_data = $biblioitem->unblessed;
    my $metadata        = $self->metadata;
    my $metadata_data   = $metadata->unblessed;

    my $new_biblio = Koha::Biblio->new($biblio_data)->store;

    $biblioitem_data->{biblionumber}     = $new_biblio->biblionumber;
    $biblioitem_data->{biblioitemnumber} = $new_biblio->biblionumber;
    Koha::Biblioitem->new($biblioitem_data)->store;

    delete $metadata_data->{id};
    $metadata_data->{biblionumber} = $new_biblio->biblionumber;
    Koha::Biblio::Metadata->new($metadata_data)->store;

    $metadata->delete;
    $biblioitem->delete;
    $self->delete;

    my $indexer = Koha::SearchEngine::Indexer->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
    $indexer->index_records( $new_biblio->biblionumber, "specialUpdate", "biblioserver" );

    return $new_biblio;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'Deletedbiblio';
}

1;
