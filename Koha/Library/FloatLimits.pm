## Please see file perltidy.ERR
## Please see file perltidy.ERR
package Koha::Library::FloatLimits;

# Copyright ByWater Solutions 2016
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Koha::Database;

use Koha::Library::FloatLimit;
use C4::Circulation qw(IsBranchTransferAllowed);

use base qw(Koha::Objects);

=head1 NAME

Koha::Library::FloatLimits - Koha Library::FloatLimit object set class

=head1 API

=head2 Class Methods

=head3 lowest_ratio_library

=cut

sub lowest_ratio_library {
    my ( $self, $item, $branchcode ) = @_;

    my $field = C4::Context->preference('item-level_itypes') ? 'items.itype' : 'biblioitems.itemtype';
    my $query = qq{
        SELECT branchcode
        FROM library_float_limits
        LEFT JOIN items ON ( items.itype = library_float_limits.itemtype AND items.holdingbranch = library_float_limits.branchcode )
        LEFT JOIN biblioitems ON ( items.biblioitemnumber = biblioitems.biblioitemnumber )
        WHERE library_float_limits.itemtype = ?
              AND ( $field = ? OR $field IS NULL )
              AND library_float_limits.float_limit != 0
        GROUP BY branchcode
        ORDER BY COUNT(items.holdingbranch)/library_float_limits.float_limit ASC, library_float_limits.float_limit DESC;
    };

    my $results = C4::Context->dbh->selectall_arrayref(
        $query, { Slice => {} }, $item->effective_itemtype,
        $item->effective_itemtype
    );

    my $UseBranchTransferLimits = C4::Context->preference("UseBranchTransferLimits");
    my $BranchTransferLimitsType =
        C4::Context->preference("BranchTransferLimitsType") eq 'itemtype' ? 'effective_itemtype' : 'ccode';

    foreach my $r (@$results) {
        if ($UseBranchTransferLimits) {
            my $allowed = C4::Circulation::IsBranchTransferAllowed(
                $r->{branchcode},    # to
                $branchcode,         # from
                $item->$BranchTransferLimitsType
            );
            return $r->{branchcode} if $allowed;
        } else {
            return $r->{branchcode};
        }
    }
}

=head3 _type

=cut

sub _type {
    return 'LibraryFloatLimit';
}

=head3 object_class

=cut

sub object_class {
    return 'Koha::Library::FloatLimit';
}

=head1 AUTHOR

Kyle M Hall <kyle@bywatersolutions.com>

=cut

1;
