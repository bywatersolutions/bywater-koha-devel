package Koha::SearchEngine::Database::Search::Patrons;

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

use C4::Context;
use Koha::Patron::Attribute::Types;

=head1 NAME

Koha::SearchEngine::Database::Search::Patrons - Database patron search (field-group model)

=head1 DESCRIPTION

Searches the patron_search_index table using FULLTEXT MATCH...AGAINST with
field-group targeting and weighted relevance scoring.

=cut

sub new {
    my ( $class, $params ) = @_;
    return bless $params // {}, $class;
}

=head2 search_patrons

Same interface as Koha::SearchEngine::Elasticsearch::Search::Patrons::search_patrons.

Returns hashref: { total => $n, hits => \@patron_ids, es_data => {}, facets => {} }

=cut

sub search_patrons {
    my ( $self, %args ) = @_;

    my $query          = $args{query};
    my $page           = $args{page}           // 1;
    my $per_page       = $args{per_page}       // 20;
    my $order_by       = $args{order_by};
    my $match          = $args{match}          // 'starts_with';
    my $column_filters = $args{column_filters} // {};
    my $filters        = $args{filters}        // {};
    my $library        = $args{library};
    my $fields         = $args{fields};

    my $dbh = C4::Context->dbh;

    my @search_groups = $self->_resolve_search_groups($fields);

    my @where;
    my @bind;

    # Main text query via FULLTEXT on the index table
    if ( defined $query && $query ne '' ) {
        my $group_placeholders = join ',', ('?') x @search_groups;
        if ( $match eq 'contains' ) {
            push @where, qq{
                b.borrowernumber IN (
                    SELECT psi.patron_id FROM patron_search_index psi
                    WHERE psi.field_group IN ($group_placeholders)
                      AND MATCH(psi.content) AGAINST(? IN BOOLEAN MODE)
                )
            };
            my $escaped = $query;
            $escaped =~ s/([+\-><()~*"@])/\\$1/g;
            push @bind, @search_groups, "*${escaped}*";
        } else {
            # starts_with: prefix match via LIKE on the index content
            push @where, qq{
                b.borrowernumber IN (
                    SELECT psi.patron_id FROM patron_search_index psi
                    WHERE psi.field_group IN ($group_placeholders)
                      AND psi.content LIKE ?
                )
            };
            push @bind, @search_groups, "$query%";
        }
    }

    # Facet filters (exact match on borrowers table)
    for my $field (qw( library_id category_id )) {
        my $db_field = $field eq 'library_id' ? 'branchcode' : 'categorycode';
        if ( my $val = $filters->{$field} ) {
            if ( ref $val eq 'ARRAY' ) {
                my $ph = join ',', ('?') x @$val;
                push @where, "b.$db_field IN ($ph)";
                push @bind,  @$val;
            } else {
                push @where, "b.$db_field = ?";
                push @bind,  $val;
            }
        }
    }

    # IndependentBranches scoping
    if ( $library && C4::Context->preference('IndependentBranches') ) {
        push @where, "b.branchcode = ?";
        push @bind,  $library;
    }

    # Column filters
    for my $field ( keys %$column_filters ) {
        my $val    = $column_filters->{$field};
        my @fields = split /:/, $field;
        my @or;
        for my $f (@fields) {
            # Search the index table for this field group
            push @or, qq{
                b.borrowernumber IN (
                    SELECT psi2.patron_id FROM patron_search_index psi2
                    WHERE psi2.field_group = ? AND psi2.content LIKE ?
                )
            };
            push @bind, $f, "%$val%";
        }
        push @where, '(' . join( ' OR ', @or ) . ')' if @or;
    }

    my $where_sql = @where ? 'WHERE ' . join( ' AND ', @where ) : '';

    # Count
    my ($total) = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM borrowers b $where_sql", undef, @bind
    );

    # Sorting
    my $order_sql = $self->_build_order_sql($order_by);

    # Pagination
    my $offset = ( $page - 1 ) * $per_page;

    my $ids = $dbh->selectcol_arrayref(
        "SELECT b.borrowernumber FROM borrowers b $where_sql $order_sql LIMIT ? OFFSET ?",
        undef, @bind, $per_page, $offset
    );

    return {
        total   => $total // 0,
        hits    => $ids // [],
        es_data => {},
        facets  => {},
    };
}

sub _resolve_search_groups {
    my ( $self, $fields ) = @_;

    if ( $fields && @$fields ) {
        return @$fields;
    }

    # Default: standard + searched_by_default attributes
    my @groups = ('standard');

    if ( C4::Context->preference('ExtendedPatronAttributes') ) {
        my $attr_types = Koha::Patron::Attribute::Types->search(
            { staff_searchable => 1, searched_by_default => 1 }
        );
        while ( my $type = $attr_types->next ) {
            push @groups, '_ATTR_' . $type->code;
        }
    }

    return @groups;
}

sub _build_order_sql {
    my ( $self, $order_by ) = @_;

    return 'ORDER BY b.surname, b.firstname' unless $order_by;

    my @sort;
    for my $field ( split /,/, $order_by ) {
        $field =~ s/^\s+|\s+$//g;
        next unless $field;

        my $direction = 'ASC';
        if ( $field =~ s/^-// ) {
            $direction = 'DESC';
        } elsif ( $field =~ s/^\+// ) {
            $direction = 'ASC';
        }

        # Map API field names to DB columns where needed
        my %field_map = (
            library_name         => 'b.branchcode',
            category_description => 'b.categorycode',
            patron_name          => 'b.surname',
            expiry_date          => 'b.dateexpiry',
            date_of_birth        => 'b.dateofbirth',
            staff_notes          => 'b.borrowernotes',
            statistics_1         => 'b.sort1',
            statistics_2         => 'b.sort2',
        );

        my $col = $field_map{$field} // "b.$field";
        next unless $col =~ /^b\.[a-z_]+$/;    # safety
        push @sort, "$col $direction";
    }

    return @sort ? 'ORDER BY ' . join( ', ', @sort ) : 'ORDER BY b.surname, b.firstname';
}

1;
