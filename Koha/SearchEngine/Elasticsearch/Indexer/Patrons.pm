package Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

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

use Carp qw( carp croak );
use Try::Tiny qw( catch try );
use YAML::XS;

use base qw(Koha::SearchEngine::Elasticsearch::Indexer);

use Koha::Exceptions;
use Koha::Exceptions::Elasticsearch;
use C4::Context;
use Koha::Patrons;
use Koha::Patron::Attribute::Types;

use constant PATRONS_INDEX => 'patrons';

=head1 NAME

Koha::SearchEngine::Elasticsearch::Indexer::Patrons - Index patron records

=head1 SYNOPSIS

    use Koha::SearchEngine::Elasticsearch::Indexer::Patrons;

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();
    $indexer->index_patrons(\@patron_ids);
    $indexer->delete_patrons(\@patron_ids);

=head1 DESCRIPTION

Handles building ES documents from patron records and indexing them.
Unlike biblio/authority indexing, patron documents are built directly
from database objects rather than MARC records.

=cut

=head2 new

    my $indexer = Koha::SearchEngine::Elasticsearch::Indexer::Patrons->new();

=cut

sub new {
    my ( $class, $params ) = @_;
    $params //= {};
    $params->{index} = PATRONS_INDEX;
    return $class->SUPER::new($params);
}

=head2 index_patrons

    $indexer->index_patrons(\@borrowernumbers);

Index or reindex the given patrons. Fetches patron data from the DB
and builds ES documents.

=cut

sub index_patrons {
    my ( $self, $patron_ids ) = @_;

    my @body;
    for my $patron_id (@$patron_ids) {
        my $patron = Koha::Patrons->find($patron_id);
        next unless $patron;

        # Skip anonymized patrons — no PII to index
        next if $patron->anonymized;

        my $document = $self->_build_document($patron);
        push @body, { index => { _id => "$patron_id" } };
        push @body, $document;
    }

    return unless @body;

    try {
        my $elasticsearch = $self->get_elasticsearch();
        my $response      = $elasticsearch->bulk(
            index => $self->index_name,
            body  => \@body,
        );
        if ( $response->{errors} ) {
            carp "Elasticsearch errors occurred when indexing patrons";
        }
        return $response;
    } catch {
        Koha::Exceptions::Elasticsearch::BadResponse->throw(
            type    => $_->{type},
            details => $_->{text},
        );
    };
}

=head2 delete_patrons

    $indexer->delete_patrons(\@borrowernumbers);

Remove patrons from the index. Used when a patron is deleted or anonymized.

=cut

sub delete_patrons {
    my ( $self, $patron_ids ) = @_;

    my @body = map { { delete => { _id => "$_" } } } @$patron_ids;

    my $elasticsearch = $self->get_elasticsearch();
    my $result        = $elasticsearch->bulk(
        index => $self->index_name,
        body  => \@body,
    );
    if ( $result->{errors} ) {
        croak "Elasticsearch error during patron bulk delete";
    }
    return $result;
}

=head2 _build_document

    my $doc = $self->_build_document($patron);

Builds an ES document hashref from a Koha::Patron object.

=cut

sub _build_document {
    my ( $self, $patron ) = @_;

    my $doc = {};

    # Core fields from the patron record — indexed using API field names
    my %api_field_map = (
        borrowernumber => 'patron_id',
        branchcode     => 'library_id',
        categorycode   => 'category_id',
        dateofbirth    => 'date_of_birth',
        dateenrolled   => 'date_enrolled',
        dateexpiry     => 'expiry_date',
        borrowernotes  => 'staff_notes',
        gonenoaddress  => 'incorrect_address',
        lost           => 'patron_card_lost',
        sort1          => 'statistics_1',
        sort2          => 'statistics_2',
        zipcode        => 'postal_code',
        othernames     => 'other_name',
        streetnumber   => 'street_number',
        streettype     => 'street_type',
        opacnote       => 'opac_notes',
    );

    my @direct_fields = qw(
        borrowernumber cardnumber surname firstname preferred_name middle_name
        othernames initials title userid
        streetnumber streettype address address2 city state zipcode country
        email emailpro B_email phone phonepro mobile B_phone altcontactphone
        B_address B_address2 B_city B_state B_zipcode B_country
        altcontactfirstname altcontactsurname
        altcontactaddress1 altcontactaddress2 altcontactaddress3
        categorycode branchcode dateofbirth dateenrolled dateexpiry
        sort1 sort2 borrowernotes opacnote
    );

    for my $field (@direct_fields) {
        my $value = $patron->$field;
        next unless defined $value && $value ne '';
        my $index_field = $api_field_map{$field} // $field;
        $doc->{$index_field} = $value;
    }

    # Boolean fields
    $doc->{restricted}         = $patron->debarred ? \1 : \0;
    $doc->{incorrect_address}  = $patron->gonenoaddress ? \1 : \0;
    $doc->{patron_card_lost}   = $patron->lost ? \1 : \0;

    # Computed fields
    $doc->{checkouts_count}      = $patron->checkouts->count;
    $doc->{account_balance}      = $patron->account->balance + 0;
    $doc->{library_name}         = $patron->library->branchname;
    $doc->{category_description} = $patron->category->description;

    # Composite field for cross-field name search
    my @name_parts = grep { defined $_ && $_ ne '' }
        map { $patron->$_ } qw(surname firstname preferred_name othernames middle_name);
    $doc->{patron_name} = join( ' ', @name_parts ) if @name_parts;

    # Autocomplete suggest field
    my @suggest_inputs = grep { defined $_ && $_ ne '' }
        map { $patron->$_ } qw(surname firstname cardnumber);
    $doc->{suggest} = { input => \@suggest_inputs } if @suggest_inputs;

    # Extended attributes
    my @attributes = $patron->extended_attributes->as_list;
    if (@attributes) {
        my @nested;
        for my $attr (@attributes) {
            my $code  = $attr->code;
            my $value = $attr->attribute;
            next unless defined $value && $value ne '';

            push @nested, { code => $code, value => $value };

            # Dynamic field per attribute code (raw value/code for filtering)
            $doc->{"ext_attr_$code"} //= [];
            push @{ $doc->{"ext_attr_$code"} }, $value;

            # Description field for search/sort (from authorised value if available)
            my $av = $attr->authorised_value;
            if ($av) {
                $doc->{"ext_attr_${code}_description"} //= [];
                push @{ $doc->{"ext_attr_${code}_description"} }, $av->lib;
            }
        }
        $doc->{extended_attributes} = \@nested if @nested;
    }

    return $doc;
}

=head2 create_index

    $indexer->create_index();

Creates the patrons index with settings and mappings.
Overrides the parent to use patron-specific mappings with dynamic templates.

=cut

sub create_index {
    my ($self) = @_;

    my $settings      = $self->get_elasticsearch_settings();
    my $elasticsearch = $self->get_elasticsearch();

    my $max_result_window = C4::Context->preference('ElasticsearchPatronMaxResultWindow') || 1_000_000;
    $settings->{index}{max_result_window} = $max_result_window;

    $elasticsearch->indices->create(
        index => $self->index_name,
        body  => { settings => $settings },
    );

    $self->update_mappings();
}

=head2 update_mappings

    $indexer->update_mappings();

Applies patron-specific mappings including dynamic templates for extended attributes.

=cut

sub update_mappings {
    my ($self) = @_;

    my $elasticsearch = $self->get_elasticsearch();
    my $mappings      = $self->get_elasticsearch_mappings();

    try {
        $elasticsearch->indices->put_mapping(
            index => $self->index_name,
            body  => $mappings,
        );
    } catch {
        $self->set_index_status_recreate_required();
        my $reason     = $_[0]->{vars}->{body}->{error}->{reason} // 'unknown';
        my $index_name = $self->index_name;
        Koha::Exception->throw(
            error => "Unable to update mappings for index \"$index_name\". Reason: \"$reason\". Index needs recreation.",
        );
    };
    $self->set_index_status_ok();
}

=head2 get_elasticsearch_mappings

Returns the ES mapping configuration for the patrons index,
including dynamic templates for extended attribute fields.

=cut

sub get_elasticsearch_mappings {
    my ($self) = @_;

    my $mappings_yaml = C4::Context->config('intranetdir')
        . '/admin/searchengine/elasticsearch/patron_mappings.yaml';
    my $config = YAML::XS::LoadFile($mappings_yaml);
    my $fields = $config->{patrons};

    my $field_config_yaml = C4::Context->config('intranetdir')
        . '/admin/searchengine/elasticsearch/field_config.yaml';
    my $field_config = YAML::XS::LoadFile($field_config_yaml);

    my %properties;

    for my $field_name ( keys %$fields ) {
        my $spec = $fields->{$field_name};
        my $type = $spec->{type} || '';

        if ( $type eq 'nested' ) {
            $properties{$field_name} = {
                type       => 'nested',
                properties => {
                    code  => { type => 'keyword' },
                    value => {
                        type     => 'text',
                        analyzer => 'analyzer_standard',
                        fields   => {
                            raw => { type => 'keyword' },
                        },
                    },
                },
            };
            next;
        }

        if ( $type eq 'date' ) {
            $properties{$field_name} = { type => 'date', format => 'yyyy-MM-dd' };
            if ( $spec->{sort} ) {
                $properties{"${field_name}__sort"} = { type => 'date', format => 'yyyy-MM-dd', index => \0 };
            }
            next;
        }

        if ( $type eq 'integer' ) {
            $properties{$field_name} = { type => 'integer' };
            next;
        }

        if ( $type eq 'number' ) {
            $properties{$field_name} = { type => 'float' };
            next;
        }

        # Get base field config from field_config.yaml
        my $search_type = $type || 'default';
        my $base_config = $field_config->{search}{$search_type}
            // $field_config->{search}{default};
        $properties{$field_name} = {%$base_config};

        # Add sort sub-field
        if ( $spec->{sort} ) {
            $properties{$field_name}{fields} //= {};
            $properties{$field_name}{fields}{sort} = $field_config->{sort}{default};
        }

        # Add facet sub-field
        if ( $spec->{facet} ) {
            $properties{$field_name}{fields} //= {};
            $properties{$field_name}{fields}{facet} = $field_config->{facet}{default};
        }
    }

    # Suggest field for autocomplete
    $properties{suggest} = $field_config->{suggestible}{default};

    return {
        properties       => \%properties,
        dynamic_templates => [
            {
                ext_attrs => {
                    match   => 'ext_attr_*',
                    mapping => {
                        type     => 'text',
                        analyzer => 'analyzer_standard',
                        fields   => {
                            raw  => { type => 'keyword' },
                            sort => $field_config->{sort}{default},
                        },
                    },
                },
            },
        ],
    };
}

1;
