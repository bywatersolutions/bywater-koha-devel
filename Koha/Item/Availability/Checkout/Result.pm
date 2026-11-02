package Koha::Item::Availability::Checkout::Result;

# Copyright 2026 Koha Development Team
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

use base 'Koha::Result::Availability';

use Koha::Item::Availability::Checkout;

=head1 NAME

Koha::Item::Availability::Checkout::Result - Typed availability result for checkout operations

=head1 DESCRIPTION

Subclass of L<Koha::Result::Availability> for checkout operations. The
confirmation token is bound to the item, the patron and the user performing
the checkout, so a token obtained for one patron cannot be used to check the
item out to another one.

=head1 API

=head2 Class methods

=head3 new

    my $result = Koha::Item::Availability::Checkout::Result->new;

Constructor.

=cut

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();
    $self->{forced} = {};
    return $self;
}

=head2 Instance methods

=head3 token_params

    my $params = $result->token_params;

Returns C<[qw(item patron user)]>. These context keys must be set before
calling C<as_token> or C<check_token>.

=cut

sub token_params { [qw(item patron user)] }

=head3 promote_confirmation

    $result->promote_confirmation( $key );

Turns the I<$key> confirmation, if present, into a blocker, keeping its
payload.

=cut

sub promote_confirmation {
    my ( $self, $key ) = @_;

    return $self unless exists $self->{confirmations}->{$key};

    $self->add_blocker( $key => delete $self->{confirmations}->{$key} );

    return $self;
}

=head3 relax_blocker

    $result->relax_blocker( $key );

Turns the I<$key> blocker, if present, into a warning and records it as
forced (see L</forced>).

=cut

sub relax_blocker {
    my ( $self, $key ) = @_;

    return $self unless exists $self->{blockers}->{$key};

    my $payload = delete $self->{blockers}->{$key};
    $self->{forced}->{$key} = $payload;
    $self->add_warning( $key => $payload );

    return $self;
}

=head3 forced

    my $forced = $result->forced;

Returns a hashref of the blockers that were overridden, by a policy (e.g.
I<OnSiteCheckoutsForce>) or by the user (I<overrides>). They are reported as
warnings too.

=cut

sub forced {
    my ($self) = @_;
    return $self->{forced};
}

=head3 legacy_override_params

    my $overrides = $result->legacy_override_params;

    AddIssue(
        $patron, $barcode, $due_date, $cancelreserve, undef, undef,
        {
            confirmations => $overrides->{confirmations},
            forced        => $overrides->{forced},
            ...
        }
    );

Returns the CanBookBeIssued (UPPERCASE) keys of the confirmations, and of the
blockers plus the forced keys, as expected by AddIssue's I<confirmations> and
I<forced> parameters (used for logging the overrides).

=cut

sub legacy_override_params {
    my ($self) = @_;

    my $class = 'Koha::Item::Availability::Checkout';

    return {
        confirmations => [ sort map { $class->legacy_from_key($_) } keys %{ $self->{confirmations} } ],
        forced        =>
            [ sort map { $class->legacy_from_key($_) } ( keys %{ $self->{blockers} }, keys %{ $self->{forced} } ) ],
    };
}

=head3 to_api

    my $hashref = $result->to_api;

Adds the I<forced> keys to L<Koha::Result::Availability/to_api>, so clients
know which blockers were overridden.

=cut

sub to_api {
    my ($self) = @_;

    my $api = $self->SUPER::to_api;
    $api->{forced} = [ sort keys %{ $self->{forced} } ];

    return $api;
}

=head1 AUTHOR

Koha Development Team <https://koha-community.org/>

=cut

1;
