package Koha::Statistics;

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

use C4::Context;
use Koha::Database;
use Koha::DateUtils;

use Koha::Statistic;

use base qw(Koha::Objects);

=head1 NAME

Koha::Statistics - Koha Statistic Object set class

=head1 API

=head2 Class Methods

=head3 invalid_patron

Koha::Statistics->invalid_patron( { patron => $cardnumber } );

=cut

sub invalid_patron {
    return unless C4::Context->preference('LogInvalidPatrons');

    my ( $class, $params ) = @_;

    my $patron = $params->{patron};
    croak('Invalid patron passed in!') unless $patron;

    return $class->_invalid_value(
        {
            type  => 'patron',
            value => $patron
        }
    );
}

=head3 invalid_item

Koha::Statistics->invalid_item( { item => $barcode } );

=cut

sub invalid_item {
    return unless C4::Context->preference('LogInvalidItems');

    my ( $class, $params ) = @_;

    my $item = $params->{item};
    croak('Invalid item passed in!') unless $item;

    return $class->_invalid_value(
        {
            type  => 'item',
            value => $item
        }
    );
}

=head3 invalid_value

Koha::Statistics->invalid_value( { type => 'patron', value => $patron } );

=cut

sub _invalid_value {
    my ( $class, $params ) = @_;

    my $type  = $params->{type};
    my $value = $params->{value};
    croak('Invalid type passed in!') unless $type eq 'patron' || $type eq 'item';
    croak('No value passed in!') unless $value;

    my $branch = C4::Context->userenv ? C4::Context->userenv->{branch} : undef;
    my $dt     = dt_from_string();
    my $associatedborrower = C4::Context->userenv->{'number'};

    return Koha::Statistic->new(
        {
            type               => "invalid_$type",
            other              => $value,
            datetime           => $dt,
            branch             => $branch,
            associatedborrower => $associatedborrower
        }
    )->store();
}

=head3 type

=cut

sub _type {
    return 'Statistic';
}

sub object_class {
    return 'Koha::Statistic';
}

1;
