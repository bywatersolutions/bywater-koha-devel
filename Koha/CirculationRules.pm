package Koha::CirculationRules;

# Copyright Vaara-kirjastot 2015
# Copyright Koha Development Team 2016
#
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

use Carp qw(croak);

use Koha::CirculationRule;

use base qw(Koha::Objects);

=head1 NAME

Koha::IssuingRules - Koha IssuingRule Object set class

=head1 API

=head2 Class Methods

=cut

=head3 get_effective_rule

=cut

sub get_effective_rule {
    my ( $self, $params ) = @_;

    my $rule_name    = $params->{rule_name};
    my $categorycode = $params->{categorycode};
    my $itemtype     = $params->{itemtype};
    my $branchcode   = $params->{branchcode};

    craok 'No rule name passed in!' unless $rule_name;

    my $params;
    $params->{rule_name} = $rule_name;
    $params->{categorycode} = { 'in' => [ $categorycode, undef ] }
      if $categorycode;
    $params->{itemtype} = { 'in' => [ $itemtype, undef ] }
      if $itemtype;
    $params->{branchcode} = { 'in' => [ $branchcode, undef ] }
      if $branchcode;

    my $rule = $self->search(
        $params,
        {
            order_by => {
                -desc => [ 'branchcode', 'categorycode', 'itemtype' ]
            },
            rows => 1,
        }
    )->single;

    return $rule;
}

=head3 type

=cut

sub _type {
    return 'CirculationRule';
}

sub object_class {
    return 'Koha::CirculationRule';
}

1;
