package Koha::SystemMessages;

# Copyright ByWater Solutions 2026
#
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

use base qw(Koha::Objects);

use Koha::DateUtils qw( dt_from_string );
use Koha::Exceptions;
use Koha::SystemMessage;

=head1 NAME

Koha::SystemMessages - Koha SystemMessages Object set class

=head1 API

=head2 Class methods

=head3 add

    my $message = Koha::SystemMessages->add( { component => 'Notices', message => $text } );

Records a message for staff to see. An uncleared message with the same component and text
is reused, bumping its occurrences and updated_date, so a repeating failure shows as one row.
Throws Koha::Exceptions::MissingParameter unless component and message are passed.

=cut

sub add {
    my ( $class, $params ) = @_;

    for my $param (qw( component message )) {
        Koha::Exceptions::MissingParameter->throw( error => "The $param parameter is mandatory" )
            unless defined $params->{$param};
    }

    my $existing = $class->search(
        {
            component    => $params->{component},
            message      => $params->{message},
            cleared_date => undef,
        }
    )->next;

    if ($existing) {
        return $existing->set(
            {
                occurrences  => $existing->occurrences + 1,
                updated_date => dt_from_string,
            }
        )->store;
    }

    # Reload so the caller sees the database defaults ( occurrences, dates )
    return Koha::SystemMessage->new(
        {
            component => $params->{component},
            message   => $params->{message},
        }
    )->store->discard_changes;
}

=head2 Internal methods

=head3 _type

=cut

sub _type {
    return 'SystemMessage';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::SystemMessage';
}

1;
