package Koha::Statistics;

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


use Koha::Database;

use Koha::Statistic;
use Koha::DateUtils qw(dt_from_string);

use base qw(Koha::Objects);

=head1 NAME

Koha::Statistics - Koha Statistic Object set class

=head1 API

=head2 Class Methods

=head3 log_invalid_patron

Koha::Statistics->log_invalid_patron( { patron => $cardnumber } );

=cut

sub log_invalid_patron {
    return unless C4::Context->preference('LogInvalidPatrons');

    my ( $class, $params ) = @_;

    my $patron = $params->{patron};

    return $class->_log_invalid_value(
        {
            type  => 'patron',
            value => $patron
        }
    );
}

=head3 log_invalid_item

Koha::Statistics->log_invalid_item( { item => $barcode } );

=cut

sub log_invalid_item {
    return unless C4::Context->preference('LogInvalidItems');

    my ( $class, $params ) = @_;

    my $item = $params->{item};

    return $class->_log_invalid_value(
        {
            type  => 'item',
            value => $item
        }
    );
}

=head3 invalid_value

Koha::Statistics->invalid_value( { type => 'patron', value => $patron } );

=cut

sub _log_invalid_value {
    my ( $class, $params ) = @_;

    my $type  = $params->{type};
    my $value = $params->{value};

    my $branch = C4::Context->userenv ? C4::Context->userenv->{branch} : undef;
    my $dt     = dt_from_string();
    my $borrowernumber = C4::Context->userenv->{'number'};

    return Koha::Statistic->new(
        {
            type           => "invalid_$type",
            other          => $value,
            itemnumber     => "",
            ccode          => "",
            itemtype       => "",
            datetime       => $dt,
            branch         => $branch,
            borrowernumber => $borrowernumber
        }
    )->store();
}

=head3 _type

=cut

sub _type {
    return 'Statistic';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::Statistic';
}

1;
