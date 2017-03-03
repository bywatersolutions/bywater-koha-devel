package Koha::RDF::Store;

# This file is part of Koha.
#
# Copyright 2017 ByWater Solutions
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

# This is a shim that gives you the appropriate search object for your
# system preference.

=head1 NAME

Koha::RDF::Store - instantiate the store object that corresponds to
the C<RDFEngine> system preference.

=head1 DESCRIPTION

This allows you to be agnostic about what the storage engine configuration is
and just get whatever search object you need.

=head1 SYNOPSIS

    use Koha::RDF::Store;
    my $store = Koha::RDF::Store->new();

=head1 METHODS

=head2 new

Creates a new C<Store> of whatever the relevant type is.

=cut

use C4::Context;
use Modern::Perl;

sub new {
    my $engine = C4::Context->preference("RDFEngine") // 'Trine';
    my $file = "Koha/RDF/${engine}/Store.pm";
    my $class = "Koha::RDF::${engine}::Store";
    require $file;
    shift @_;
    return $class->new(@_);
}

1;
