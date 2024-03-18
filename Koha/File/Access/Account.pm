package Koha::File::Access::Account;

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

use Carp qw( carp );
use DateTime;
use Encode qw( from_to );
use English qw{ -no_match_vars };
use File::Copy qw( copy move );
use File::Slurp qw( read_file );
use Net::FTP;
use Net::SFTP::Foreign;

use Koha::Encryption;

use Koha::Database;

use base qw(Koha::Object);

=head1 NAME

Koha::File::Access::Account - Koha object class to represent a remote file server

=head1 API

=head2 Class Methods

=cut

sub download {
    my ( $self, $params ) = @_;

    if ( $self->transport eq 'SFTP' ) {
        return $self->download_sftp($params);
    }
    if ( $self->transport eq 'FTP' ) {
        return $self->download_ftp($params);
    }
    elsif ( $self->transport eq 'LOCAL' ) {
        return $self->download_local($params);
    }
}

=head3 _type

=cut

sub _type {
    return 'FileAccessAccount';
}

1;
