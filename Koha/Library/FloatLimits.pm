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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;

use Koha::Database;

use Koha::Library::FloatLimit;
use Koha::Libraries;
use C4::Circulation qw(IsBranchTransferAllowed);

use base qw(Koha::Objects);

=head1 NAME

Koha::Library::FloatLimits - Koha Library::FloatLimit object set class

=head1 API

=head2 Class Methods

=head3 lowest_ratio_library

    my $library = Koha::Library::FloatLimits->lowest_ratio_library(
        $item, $branchcode, $from_branch
    );

Determines the optimal library to transfer an item to based on float limit ratios.

This method calculates the ratio of current items to float limits for each library
with configured float limits for the item's type. It considers items currently at
the branch, items in transit to/from the branch, and respects library group
restrictions if the item's return policy is set to 'returnbylibrarygroup'.

The method returns the library with the lowest ratio (most need for this item type),
with preference given to the current branch in case of ties. Returns undef if no
suitable transfer destination is found or if branch transfer limits prevent the
transfer.

=over 4

=item * $item - Koha::Item object to be transferred

=item * $branchcode - branchcode of the return/checkin location

=item * $from_branch - (optional) branchcode where item was previously held, used for
adjusting item counts during the calculation

=back

Returns: Koha::Library object of the destination branch, or undef if no transfer needed

=cut

sub lowest_ratio_library {
    my ( $self, $item, $branchcode, $from_branch ) = @_;
    my $schema = Koha::Database->new->schema;

    my @float_limits = $schema->resultset('LibraryFloatLimit')->search(
        {
            itemtype    => $item->effective_itemtype,
            float_limit => { '!=' => 0 }
        }
    )->all;

    # check the items return policy
    my $hbr = Koha::CirculationRules->get_return_branch_policy($item);

    # if item only floats in the library group we must eliminate all other candidates
    if ( $hbr && $hbr eq 'returnbylibrarygroup' ) {
        my $current_library = Koha::Libraries->find($branchcode);
        my $float_libraries = $current_library->get_float_libraries;

        if ( $float_libraries->count > 0 ) {
            my @allowed_branchcodes = $float_libraries->get_column('branchcode');
            my %allowed_branches    = map { $_ => 1 } @allowed_branchcodes;
            @float_limits = grep { $allowed_branches{ $_->get_column('branchcode') } } @float_limits;
        }
    }

    return unless @float_limits;

    my @candidates;
    my $use_item_level     = C4::Context->preference('item-level_itypes');
    my $effective_itemtype = $item->effective_itemtype;

    # Build hash of float limits for quick lookup
    my %float_limit_by_branch = map { $_->get_column('branchcode') => $_->get_column('float_limit') } @float_limits;
    my @branch_codes          = keys %float_limit_by_branch;

    # Get item counts at branches in a single aggregated query
    my %at_branch_counts;
    if ($use_item_level) {
        my $at_branch_rs = $schema->resultset('Item')->search(
            {
                itype         => $effective_itemtype,
                holdingbranch => { -in => \@branch_codes },
                onloan        => undef
            },
            {
                select   => [ 'holdingbranch', { count => 'itemnumber', -as => 'item_count' } ],
                as       => [ 'holdingbranch', 'item_count' ],
                group_by => ['holdingbranch']
            }
        );
        while ( my $row = $at_branch_rs->next ) {
            $at_branch_counts{ $row->get_column('holdingbranch') } = $row->get_column('item_count');
        }
    } else {
        my $at_branch_rs = $schema->resultset('Item')->search(
            {
                holdingbranch         => { -in => \@branch_codes },
                'biblioitem.itemtype' => $effective_itemtype,
                onloan                => undef
            },
            {
                join     => 'biblioitem',
                select   => [ 'me.holdingbranch', { count => 'me.itemnumber', -as => 'item_count' } ],
                as       => [ 'holdingbranch',    'item_count' ],
                group_by => ['me.holdingbranch']
            }
        );
        while ( my $row = $at_branch_rs->next ) {
            $at_branch_counts{ $row->get_column('holdingbranch') } = $row->get_column('item_count');
        }
    }

    # Get items in transit TO branches in a single aggregated query
    my %in_transit_to_counts;
    my $to_transit_rs = $schema->resultset('Item')->search(
        { 'me.itype' => $effective_itemtype },
        {
            join  => 'branchtransfers',
            where => {
                'branchtransfers.tobranch'      => { -in => \@branch_codes },
                'branchtransfers.datearrived'   => undef,
                'branchtransfers.datecancelled' => undef,
            },
            select => [ 'branchtransfers.tobranch', { count => { distinct => 'me.itemnumber' }, -as => 'item_count' } ],
            as     => [ 'tobranch',                 'item_count' ],
            group_by => ['branchtransfers.tobranch']
        }
    );
    while ( my $row = $to_transit_rs->next ) {
        $in_transit_to_counts{ $row->get_column('tobranch') } = $row->get_column('item_count');
    }

    # Get items in transit FROM branches in a single aggregated query
    my %in_transit_from_counts;
    my $from_transit_rs = $schema->resultset('Item')->search(
        { 'me.itype' => $effective_itemtype },
        {
            join  => 'branchtransfers',
            where => {
                'branchtransfers.frombranch'    => { -in => \@branch_codes },
                'branchtransfers.datearrived'   => undef,
                'branchtransfers.datecancelled' => undef,
            },
            select =>
                [ 'branchtransfers.frombranch', { count => { distinct => 'me.itemnumber' }, -as => 'item_count' } ],
            as       => [ 'frombranch', 'item_count' ],
            group_by => ['branchtransfers.frombranch']
        }
    );
    while ( my $row = $from_transit_rs->next ) {
        $in_transit_from_counts{ $row->get_column('frombranch') } = $row->get_column('item_count');
    }

    # Calculate ratios for each branch using the aggregated counts
    foreach my $branch (@branch_codes) {
        my $float_limit_val = $float_limit_by_branch{$branch};

        my $item_count =
            ( $at_branch_counts{$branch}       || 0 ) +
            ( $in_transit_to_counts{$branch}   || 0 ) -
            ( $in_transit_from_counts{$branch} || 0 );

        # Artificially adjust counts for the item being checked in
        if ($from_branch) {

            # This is the checkin branch - artificially add 1
            $item_count++ if $branch eq $branchcode;

            # This is where the item came from - artificially subtract 1
            $item_count-- if $branch eq $from_branch;
        }

        # Guard against division by zero (float_limit_val should never be 0 due to search filter, but be safe)
        my $ratio = $float_limit_val > 0 ? $item_count / $float_limit_val : 999999;

        push @candidates, {
            branchcode  => $branch,
            ratio       => $ratio,
            float_limit => $float_limit_val
        };
    }

    # sort the branches by lowest ratio
    # in the event of a tie the item should stay where it is, if the current branch is involved in the tie
    # when the current branch is not involved in the tie a random branch is chosen from those who tied
    @candidates = sort {
               $a->{ratio} <=> $b->{ratio}
            || ( $a->{branchcode} eq $branchcode ? -1 : 0 ) - ( $b->{branchcode} eq $branchcode ? -1 : 0 )
            || rand() <=> rand()
    } @candidates;

    my $UseBranchTransferLimits = C4::Context->preference("UseBranchTransferLimits");
    my $BranchTransferLimitsType =
        C4::Context->preference("BranchTransferLimitsType") eq 'itemtype' ? 'effective_itemtype' : 'ccode';

    my $transfer_branch;
    for my $candidate (@candidates) {

        if ($UseBranchTransferLimits) {
            my $allowed = C4::Circulation::IsBranchTransferAllowed(
                $candidate->{branchcode},
                $branchcode,
                $item->$BranchTransferLimitsType
            );

            $transfer_branch = Koha::Libraries->find( $candidate->{branchcode} ) if $allowed;
            last;
        } else {
            $transfer_branch = Koha::Libraries->find( $candidate->{branchcode} );
            last;
        }
    }

    return $transfer_branch;
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
