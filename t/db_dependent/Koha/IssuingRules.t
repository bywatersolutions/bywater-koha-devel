#!/usr/bin/perl

# Copyright 2016 Koha-Suomi Oy
#
# This file is part of Koha
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

use Test::More tests => 1;

use Benchmark;

use Koha::CirculationRules;

use t::lib::TestBuilder;

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

my $builder      = t::lib::TestBuilder->new;

subtest 'get_effective_issuing_rule' => sub {
    plan tests => 3;

    my $patron       = $builder->build({ source => 'Borrower' });
    my $item     = $builder->build({ source => 'Item' });

    my $categorycode = $patron->{'categorycode'};
    my $itemtype     = $item->{'itype'};
    my $branchcode   = $item->{'homebranch'};

    subtest 'Call with undefined values' => sub {
        plan tests => 4;

        my $rule;
        Koha::CirculationRules->delete;

        is(Koha::CirculationRules->search->count, 0, 'There are no issuing rules.');
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => undef,
            categorycode => undef,
            itemtype     => undef,
            rule_name    => 'fine',
        });
        is($rule, undef, 'When I attempt to get effective issuing rule by'
           .' providing undefined values, then undef is returned.');
        ok(Koha::CirculationRule->new({
            branchcode => '*',
            categorycode => '*',
            itemtype => '*',
            rule_name => 'fine',
        })->store, 'Given I added an issuing rule branchcode => *,'
           .' categorycode => *, itemtype => *,');
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => '*',
            categorycode => '*',
            itemtype     => '*',
            rule_name    => 'fine',
        });
        ok(_row_match($rule, '*', '*', '*'), 'When I attempt to get effective'
           .' issuing rule by providing undefined values, then the above one is'
           .' returned.');
    };

    subtest 'Get effective issuing rule in correct order' => sub {
        plan tests => 18;

        my $rule;
        Koha::CirculationRules->delete;
        is(Koha::CirculationRules->search->count, 0, 'There are no issuing rules.');
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        is($rule, undef, 'When I attempt to get effective issuing rule, then undef'
                        .' is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => '*',
            categorycode => '*',
            itemtype => '*',
            rule_name => 'fine',
        })->store, 'Given I added an issuing rule branchcode => *, categorycode => *, itemtype => *,');
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, '*', '*', '*'), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => '*',
            categorycode => '*',
            itemtype => $itemtype,
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => *, categorycode => *, itemtype => $itemtype,");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, '*', '*', $itemtype), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => '*',
            categorycode => $categorycode,
            itemtype => '*',
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => *, categorycode => $categorycode, itemtype => *,");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, '*', $categorycode, '*'), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => '*',
            categorycode => $categorycode,
            itemtype => $itemtype,
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => *, categorycode => $categorycode, itemtype => $itemtype,");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, '*', $categorycode, $itemtype), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => $branchcode,
            categorycode => '*',
            itemtype => '*',
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => $branchcode, categorycode => '*', itemtype => '*',");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, $branchcode, '*', '*'), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => $branchcode,
            categorycode => '*',
            itemtype => $itemtype,
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => $branchcode, categorycode => '*', itemtype => $itemtype,");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, $branchcode, '*', $itemtype), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => $branchcode,
            categorycode => $categorycode,
            itemtype => '*',
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => $branchcode, categorycode => $categorycode, itemtype => '*',");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, $branchcode, $categorycode, '*'), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');

        ok(Koha::CirculationRule->new({
            branchcode => $branchcode,
            categorycode => $categorycode,
            itemtype => $itemtype,
            rule_name => 'fine',
        })->store, "Given I added an issuing rule branchcode => $branchcode, categorycode => $categorycode, itemtype => $itemtype,");
        $rule = Koha::CirculationRules->get_effective_rule({
            branchcode   => $branchcode,
            categorycode => $categorycode,
            itemtype     => $itemtype,
            rule_name    => 'fine',
        });
        ok(_row_match($rule, $branchcode, $categorycode, $itemtype), 'When I attempt to get effective issuing rule,'
           .' then the above one is returned.');
    };

    subtest 'Performance' => sub {
        plan tests => 4;

        my $worst_case = timethis(500,
                    sub { Koha::CirculationRules->get_effective_rule({
                            branchcode   => 'nonexistent',
                            categorycode => 'nonexistent',
                            itemtype     => 'nonexistent',
                            rule_name    => 'nonexistent',
                        });
                    }
                );
        my $mid_case = timethis(500,
                    sub { Koha::CirculationRules->get_effective_rule({
                            branchcode   => $branchcode,
                            categorycode => 'nonexistent',
                            itemtype     => 'nonexistent',
                            rule_name    => 'nonexistent',
                        });
                    }
                );
        my $sec_best_case = timethis(500,
                    sub { Koha::CirculationRules->get_effective_rule({
                            branchcode   => $branchcode,
                            categorycode => $categorycode,
                            itemtype     => 'nonexistent',
                            rule_name    => 'nonexistent',
                        });
                    }
                );
        my $best_case = timethis(500,
                    sub { Koha::CirculationRules->get_effective_rule({
                            branchcode   => $branchcode,
                            categorycode => $categorycode,
                            itemtype     => $itemtype,
                            rule_name    => 'nonexistent',
                        });
                    }
                );
        ok($worst_case, 'In worst case, get_effective_issuing_rule finds matching'
           .' rule '.sprintf('%.2f', $worst_case->iters/$worst_case->cpu_a)
           .' times per second.');
        ok($mid_case, 'In mid case, get_effective_issuing_rule finds matching'
           .' rule '.sprintf('%.2f', $mid_case->iters/$mid_case->cpu_a)
           .' times per second.');
        ok($sec_best_case, 'In second best case, get_effective_issuing_rule finds matching'
           .' rule '.sprintf('%.2f', $sec_best_case->iters/$sec_best_case->cpu_a)
           .' times per second.');
        ok($best_case, 'In best case, get_effective_issuing_rule finds matching'
           .' rule '.sprintf('%.2f', $best_case->iters/$best_case->cpu_a)
           .' times per second.');
    };
};

sub _row_match {
    my ($rule, $branchcode, $categorycode, $itemtype) = @_;

    return $rule->branchcode eq $branchcode && $rule->categorycode eq $categorycode
            && $rule->itemtype eq $itemtype;
}

$schema->storage->txn_rollback;

1;
