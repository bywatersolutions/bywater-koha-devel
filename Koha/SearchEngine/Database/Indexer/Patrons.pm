package Koha::SearchEngine::Database::Indexer::Patrons;

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
use Koha::Patrons;
use Koha::Patron::Attribute::Types;

=head1 NAME

Koha::SearchEngine::Database::Indexer::Patrons - Database patron indexer (field-group model)

=head1 DESCRIPTION

Indexes patron data into a denormalized table using one row per patron per
field group. Each row contains concatenated text for that group, with a
FULLTEXT index on the content column. This enables targeted search by field
group and weighted relevance scoring.

=cut

my %FIELD_GROUPS = (
    standard     => [qw(surname firstname preferred_name middle_name othernames cardnumber userid)],
    full_address => [qw(address address2 city state postal_code country)],
    all_emails   => [qw(email emailpro)],
    all_phones   => [qw(phone mobile phonepro)],
);

my %DB_TO_FIELD = (
    zipcode       => 'postal_code',
    emailpro      => 'emailpro',
    phonepro      => 'phonepro',
    borrowernotes => 'staff_notes',
    sort1         => 'statistics_1',
    sort2         => 'statistics_2',
);

# Individual fields that get their own row
my @INDIVIDUAL_FIELDS = qw(
    cardnumber surname firstname preferred_name middle_name othernames userid
    email emailpro phone mobile phonepro
    address address2 city state zipcode country
    borrowernotes sort1 sort2
);

sub new {
    my ( $class, $params ) = @_;
    return bless $params // {}, $class;
}

=head2 index_patrons

    $indexer->index_patrons( \@patron_ids );

=cut

sub index_patrons {
    my ( $self, $patron_ids ) = @_;

    my $dbh = C4::Context->dbh;

    for my $id (@$patron_ids) {
        my $patron = Koha::Patrons->find($id);
        next unless $patron;
        $self->_index_patron( $dbh, $patron );
    }

    return;
}

=head2 delete_patrons

    $indexer->delete_patrons( \@patron_ids );

=cut

sub delete_patrons {
    my ( $self, $patron_ids ) = @_;

    my $dbh          = C4::Context->dbh;
    my $placeholders = join ',', ('?') x @$patron_ids;
    $dbh->do( "DELETE FROM patron_search_index WHERE patron_id IN ($placeholders)", undef, @$patron_ids );

    return;
}

=head2 rebuild

    $indexer->rebuild( verbose => 1 );

=cut

sub rebuild {
    my ( $self, %args ) = @_;

    my $dbh     = C4::Context->dbh;
    my $verbose = $args{verbose};

    $dbh->do("TRUNCATE TABLE patron_search_index");

    my $patrons = Koha::Patrons->search( { anonymized => 0 } );
    my $total   = $patrons->count;
    my $count   = 0;

    while ( my $patron = $patrons->next ) {
        $self->_index_patron( $dbh, $patron );
        $count++;
        if ( $verbose && $count % 5000 == 0 ) {
            printf "  Indexed %d / %d (%.1f%%)\n", $count, $total, ( $count / $total * 100 );
        }
    }

    printf "Indexed %d patrons\n", $count if $verbose;
    return $count;
}

sub _index_patron {
    my ( $self, $dbh, $patron ) = @_;

    my $patron_id = $patron->borrowernumber;

    # Remove existing rows for this patron
    $dbh->do( "DELETE FROM patron_search_index WHERE patron_id = ?", undef, $patron_id );

    my $sth = $dbh->prepare("INSERT INTO patron_search_index (patron_id, field_group, content) VALUES (?, ?, ?)");

    # Individual fields
    for my $field (@INDIVIDUAL_FIELDS) {
        my $value = $patron->$field;
        next unless defined $value && $value ne '';
        my $group = $DB_TO_FIELD{$field} // $field;
        $sth->execute( $patron_id, $group, $value );
    }

    # Field groups (concatenated)
    for my $group ( keys %FIELD_GROUPS ) {
        my @values = grep { defined $_ && $_ ne '' }
            map { $patron->$_ } @{ $FIELD_GROUPS{$group} };
        next unless @values;
        $sth->execute( $patron_id, $group, join( ' ', @values ) );
    }

    # Extended attributes
    for my $attr ( $patron->extended_attributes->as_list ) {
        my $value = $attr->attribute;
        next unless defined $value && $value ne '';
        $sth->execute( $patron_id, '_ATTR_' . $attr->code, $value );
    }

    # 'all' group: everything concatenated
    my @all_parts;
    for my $field (@INDIVIDUAL_FIELDS) {
        my $value = $patron->$field;
        push @all_parts, $value if defined $value && $value ne '';
    }
    push @all_parts, $patron->branchcode  // '';
    push @all_parts, $patron->categorycode // '';
    for my $attr ( $patron->extended_attributes->as_list ) {
        push @all_parts, $attr->attribute if defined $attr->attribute && $attr->attribute ne '';
    }
    my $all_content = join ' ', grep { $_ ne '' } @all_parts;
    $sth->execute( $patron_id, 'all', $all_content ) if $all_content;

    return;
}

1;
