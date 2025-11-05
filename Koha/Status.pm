package Koha::Status;

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

use Koha;

=head1 NAME

Koha::Status - Koha instance status information

=head1 SYNOPSIS

    use Koha::Status;

    my $status = Koha::Status->new();
    my $version_info = $status->version();

=head1 DESCRIPTION

This class provides methods to retrieve status information about the Koha instance.

=head1 METHODS

=head2 new

    my $status = Koha::Status->new();

Constructor.

=cut

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

=head2 version

    my $version_info = $status->version();

Returns version information in a structured format similar to
Koha::Template::Plugin::Koha->Version but with additional metadata.

Returns a hashref with the following structure:
- version: full version string
- major: major version number
- minor: minor version number
- release: major.minor version
- maintenance: major.minor.maintenance version
- development: development version (if applicable)

=cut

sub version {
    my ($self) = @_;

    my $version_string = Koha::version();
    my ( $major, $minor, $maintenance, $development ) = split( '\.', $version_string );

    return {
        version     => $version_string,
        major       => $major,
        minor       => $minor,
        release     => $major . "." . $minor,
        maintenance => $major . "." . $minor . "." . $maintenance,
        development => ( $development && $development ne '000' ) ? $development : undef,
    };
}

1;
