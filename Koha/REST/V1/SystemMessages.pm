package Koha::REST::V1::SystemMessages;

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

use Mojo::Base 'Mojolicious::Controller';

use Koha::DateUtils qw( dt_from_string );
use Koha::SystemMessages;

use Try::Tiny qw( catch try );

=head1 API

=head2 Methods

=head3 list

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    return try {
        return $c->render(
            status  => 200,
            openapi => $c->objects->search( Koha::SystemMessages->new )
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 clear

=cut

sub clear {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $message = Koha::SystemMessages->find( $c->param('system_message_id') );
        return $c->render_resource_not_found("System message")
            unless $message;

        $message->clear->discard_changes;

        return $c->render(
            status  => 200,
            openapi => $c->objects->to_api($message),
        );
    } catch {
        $c->unhandled_exception($_);
    };
}

=head3 clear_all

=cut

sub clear_all {
    my $c = shift->openapi->valid_input or return;

    return try {
        Koha::SystemMessages->search( { cleared_date => undef } )
            ->update( { cleared_date => dt_from_string }, { no_triggers => 1 } );

        return $c->render( status => 204, openapi => q{} );
    } catch {
        $c->unhandled_exception($_);
    };
}

1;
