package Koha::Acquisition::Utils;

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

use C4::Context;

=head1 NAME

Koha::Acquisition::Utils - Additional Koha functions for dealing with orders and acquisitions

=head1 SUBROUTINES

=head3 get_infos_syspref($syspref_name, $record, $field_list)

my $data = Koha::Acquisition::Utils::get_infos_syspref('MarcFieldsToOrder', $marcrecord, ['price', 'quantity', 'budget_code', etc.]);

This subroutine accepts a syspref ( MarcFieldsToOrder ),
a marc record, and an arrayref of fields to retrieve.

The return value is a hashref of key value pairs, where the keys are the field list parameters,
and the values are extracted from the MARC record based on the key to MARC field mapping from the
given system preference.

=cut

sub get_infos_syspref {
    my ($syspref_name, $record, $field_list) = @_;
    my $syspref = C4::Context->preference($syspref_name);
    $syspref = "$syspref\n\n"; # YAML is anal on ending \n. Surplus does not hurt
    my $yaml = eval {
        YAML::Load($syspref);
    };
    if ( $@ ) {
        warn "Unable to parse $syspref syspref : $@";
        return ();
    }
    my $r;
    for my $field_name ( @$field_list ) {
        next unless exists $yaml->{$field_name};
        my @fields = split /\|/, $yaml->{$field_name};
        for my $field ( @fields ) {
            my ( $f, $sf ) = split /\$/, $field;
            next unless $f and $sf;
            if ( my $v = $record->subfield( $f, $sf ) ) {
                $r->{$field_name} = $v;
            }
            last if $yaml->{$field};
        }
    }
    return $r;
}

=head3 GetMarcItemFieldsToOrderValues($syspref_name, $record, $field_list)

my $data = GetMarcItemFieldsToOrderValues('MarcItemFieldsToOrder', $marcrecord, ['homebranch', 'holdingbranch', 'itype', 'nonpublic_note', 'public_note', 'loc', 'ccode', 'notforloan', 'uri', 'copyno', 'price', 'replacementprice', 'itemcallnumber', 'quantity', 'budget_code']);

This subroutine accepts a syspref ( MarcItemFieldsToOrder ),
a marc record, and an arrayref of fields to retrieve.

The return value is a hashref of key value pairs, where the keys are the field list parameters,
and the values are extracted from the MARC record based on the key to MARC field mapping from the
given system preference.

The largest difference between get_infos_syspref and GetMarcItemFieldsToOrderValues is that the former deals
with singular marc fields, while the latter works on multiple matching marc fields and returns -1 if it cannot
find a matching number of all fields to be looked up.

=cut

sub GetMarcItemFieldsToOrderValues {
    my ($syspref_name, $record, $field_list) = @_;
    my $syspref = C4::Context->preference($syspref_name);
    $syspref = "$syspref\n\n"; # YAML is anal on ending \n. Surplus does not hurt
    my $yaml = eval {
        YAML::Load($syspref);
    };
    if ( $@ ) {
        warn "Unable to parse $syspref syspref : $@";
        return ();
    }
    my @result;
    my @tags_list;

    # Check tags in syspref definition
    for my $field_name ( @$field_list ) {
        next unless exists $yaml->{$field_name};
        my @fields = split /\|/, $yaml->{$field_name};
        for my $field ( @fields ) {
            my ( $f, $sf ) = split /\$/, $field;
            next unless $f and $sf;
            push @tags_list, $f;
        }
    }
    @tags_list = List::MoreUtils::uniq(@tags_list);

    my $tags_count = equal_number_of_fields(\@tags_list, $record);
    # Return if the number of these fields in the record is not the same.
    return -1 if $tags_count == -1;

    # Gather the fields
    my $fields_hash;
    foreach my $tag (@tags_list) {
        my @tmp_fields;
        foreach my $field ($record->field($tag)) {
            push @tmp_fields, $field;
        }
        $fields_hash->{$tag} = \@tmp_fields;
    }

    for (my $i = 0; $i < $tags_count; $i++) {
        my $r;
        for my $field_name ( @$field_list ) {
            next unless exists $yaml->{$field_name};
            my @fields = split /\|/, $yaml->{$field_name};
            for my $field ( @fields ) {
                my ( $f, $sf ) = split /\$/, $field;
                next unless $f and $sf;
                my $v = $fields_hash->{$f}[$i] ? $fields_hash->{$f}[$i]->subfield( $sf ) : undef;
                $r->{$field_name} = $v if (defined $v);
                last if $yaml->{$field};
            }
        }
        push @result, $r;
    }
    return \@result;
}

=head3 equal_number_of_fields($tags_list, $record)

$value = equal_number_of_fields(\@tags_list, $record);

Returns -1 if the number of instances of the given tags are not equal.

For example, if you need to verify there are equal 975$i's and 975$a's,
this will let you know.

=cut

sub equal_number_of_fields {
    my ($tags_list, $record) = @_;
    my $tag_fields_count;
    for my $tag (@$tags_list) {
        my @fields = $record->field($tag);
        $tag_fields_count->{$tag} = scalar @fields;
    }

    my $tags_count;
    foreach my $key ( keys %$tag_fields_count ) {
        if ( $tag_fields_count->{$key} > 0 ) { # Having 0 of a field is ok
            $tags_count //= $tag_fields_count->{$key}; # Start with the count from the first occurrence
            return -1 if $tag_fields_count->{$key} != $tags_count; # All counts of various fields should be equal if they exist
        }
    }

    return $tags_count;
}

1;
__END__

=head1 AUTHOR

Koha Development Team <http://koha-community.org/>

=cut
