package Koha::REST::V1::RPC::Biblios;

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

use Mojo::Base 'Mojolicious::Controller';

use Try::Tiny qw( catch try );

=head1 API

=head2 Methods

=head3 populate_empty_callnumbers

Controller function that handles populating empty callnumbers

=cut

sub populate_empty_callnumbers {
    my $c = shift->openapi->valid_input or return;

    my $biblio = Koha::Biblios->find( $c->param('biblio_id') );

    return $c->render_resource_not_found("Bibliographic record")
        unless $biblio;

    my $items = $biblio->items->search(
        {
            -or => [
                itemcallnumber => undef,
                itemcallnumber => q{},
            ]
        }
    );

    $items = $items->search( { itemnumber => $c->param('item_id') } )
        if $c->param('item_id');

    return try {

        my $cn_fields = C4::Context->preference('itemcallnumber');
        return $c->render(
            status  => 409,
            openapi => {
                error      => "Callnumber fields not found",
                error_code => 'missing_configuration',
            }
        ) unless $cn_fields;

        my $record = $biblio->record;
        my $callnumber;

        foreach my $callnumber_marc_field ( split( /,/, $cn_fields ) ) {
            my $callnumber_tag       = substr( $callnumber_marc_field, 0, 3 );
            my $callnumber_subfields = substr( $callnumber_marc_field, 3 );

            next unless $callnumber_tag && $callnumber_subfields;

            my $field = $record->field($callnumber_tag);

            next unless $field;

            $callnumber = $field->as_string( $callnumber_subfields, '' );
            last if $callnumber;
        }

        return $c->render(
            status  => 409,
            openapi => {
                error      => "Callnumber empty in bibliographic record",
                error_code => 'callnumber_empty',
            }
        ) unless $callnumber;

        return $c->render(
            status  => 200,
            openapi => {
                updated_items_count => 0,
                callnumber          => $callnumber
            },
        ) unless $items->count;

        my ($res) = $items->batch_update( { new_values => { itemcallnumber => $callnumber } } );
        my @modified_itemnumbers = @{ $res->{modified_itemnumbers} };

        return $c->render(
            status  => 200,
            openapi => {
                updated_items_count => scalar @modified_itemnumbers,
                callnumber          => $callnumber,
                modified_item_ids   => \@modified_itemnumbers,
            },
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
