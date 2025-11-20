use Modern::Perl;

return {
    bug_number  => "23415",
    description =>
        "Rename OPACFineNoRenewals and related sysprefs, add new sysprefs AllowFineOverrideRenewing and FineNoRenewalsBlockSelfCheckRenew",
    up => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            UPDATE IGNORE systempreferences SET variable = "FineNoRenewals", explanation = "Fine limit above which user or staff cannot renew items" WHERE variable = "OPACFineNoRenewals";
        }
        );

        say $out "Updated system preference 'OPACFineNoRenewals' to 'FineNoRenewals'";

        $dbh->do(
            q{
            UPDATE IGNORE systempreferences SET variable = "FineNoRenewalsIncludeCredits" WHERE variable = "OPACFineNoRenewalsIncludeCredits";
        }
        );

        say $out "Updated system preference 'OPACFineNoRenewalsIncludeCredits' to 'FineNoRenewalsIncludeCredits'";

        $dbh->do(
            q{
            UPDATE IGNORE systempreferences SET variable = "FineNoRenewalsBlockAutoRenew" WHERE variable = "OPACFineNoRenewalsBlockAutoRenew";
        }
        );

        say $out "Updated system preference 'OPACFineNoRenewalsBlockAutoRenew' to 'FineNoRenewalsBlockAutoRenew'";

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('AllowFineOverrideRenewing', '0', '0', 'If on, staff will be able to renew items for patrons with fines greater than FineNoRenewals.','YesNo')
        }
        );

        say $out "Added new system preference 'AllowFineOverrideRenewing'";

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('FineNoRenewalsBlockSelfCheckRenew', '0', '', 'Block self-checkout renewals if the patron owes more than the value of FineNoRenewals.','YesNo')
        }
        );

        say $out "Added new system preference 'FineNoRenewalsBlockSelfCheckRenew'";
    },
};
