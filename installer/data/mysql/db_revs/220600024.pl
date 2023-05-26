use Modern::Perl;

use Koha::CirculationRules;

return {
    bug_number => "29012",
    description => "Some rules are not saved when left blank while editing a 'rule' line in smart-rules.pl",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};
        my %default_rule_values = (
            issuelength             => 0,
            hardduedate             => '',
            unseen_renewals_allowed   => '',
            rentaldiscount          => 0,
            decreaseloanholds       => '',
        );

        my $rules = Koha::CirculationRules->search( { rule_name => 'suspension_chargeperiod' } );
        while ( my $rule = $rules->next ) {
            foreach my $key ( keys %default_rule_values ) {
                next
                  if # If there is a rule matching these criteria with defined value, we can skip it.
                  Koha::CirculationRules->search(
                    {
                        branchcode   => $rule->branchcode,
                        categorycode => $rule->categorycode,
                        itemtype     => $rule->itemtype,
                        rule_name    => $key,
                    }
                )->count;

                my $derived_rule = Koha::CirculationRules->get_effective_rule(
                    {
                        branchcode   => $rule->branchcode,
                        categorycode => $rule->categorycode,
                        itemtype     => $rule->itemtype,
                        rule_name    => $key,
                    }
                );
                my $value =
                    $derived_rule
                  ? $derived_rule->rule_value // $default_rule_values{$key}
                  : $default_rule_values{$key};

                Koha::CirculationRule->new(
                    {
                        branchcode   => $rule->branchcode,
                        categorycode => $rule->categorycode,
                        itemtype     => $rule->itemtype,
                        rule_name    => $key,
                        rule_value   => $value,
                    }
                )->store();
            }
        }

        say $out "Set derived values for blank circulation rules that weren't saved to the database";
    },
}
