use Modern::Perl;

return {
    bug_number  => "23415",
    description => "Rename OPACFineNoRenewals and add new syspref AllowFineOverrideRenewing",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            UPDATE IGNORE systempreferences SET variable = "FineNoRenewals", explanation = "Fine limit above which user or staff cannot renew items" WHERE variable = "OPACFineNoRenewals";
        }
        );

        say $out "Updated system preference 'OPACFineNoRenewals'";

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('AllowFineOverrideRenewing', '0', '0', 'If on, staff will be able to renew items for patrons with fines greater than FineNoRenewals.','YesNo')
        }
        );

        say $out "Added new system preference 'AllowFineOverrideRenewing'";
    },
};
