package Koha::Reports;

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

use Koha::Database;

use Koha::Report;

use base qw(Koha::Objects);

=head1 NAME

Koha::Reports - Koha Report Object set class

=head1 API

=head2 Class Methods

=cut

=head3 running

Returns a list of reports that are currently running

my @query_ids = Koha::Reports->running({ [ user_id => $user->userid ] });

=cut

sub running {
    my ( $self, $params ) = @_;

    my $user_id   = $params->{user_id};
    my $report_id = $params->{report_id};

    my $dbh = Koha::Database->dbh;

    my $query = q{
        SELECT id, info
         FROM information_schema.processlist
        WHERE command != 'Sleep'
          AND info LIKE '%saved_sql.id%'
    };

    my @ids;

    my $sth = $dbh->prepare($query);
    $sth->execute();
    while ( my $row = $sth->fetchrow_hashref ) {
        if ($user_id) {
            next unless $row->{info} =~ /{ user_id: $user_id }/;
        }
        if ($report_id) {
            next unless $row->{info} =~ /{ saved_sql.id: $report_id }/;
        }
        push @ids, $row->{id};
    }

    return @ids;
}

=head3 _type

Returns name of corresponding DBIC resultset

=cut

sub _type {
    return 'SavedSql';
}

=head3 object_class

Returns name of corresponding Koha Object Class

=cut

sub object_class {
    return 'Koha::Report';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
