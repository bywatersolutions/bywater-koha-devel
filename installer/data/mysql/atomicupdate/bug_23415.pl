use Modern::Perl;

return {
    bug_number  => "23415",
    description => "Rename OPACFineNoRenewals",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            UPDATE systempreferences SET variable = "FineNoRenewals", explanation = "Fine limit above which user or staff cannot renew items" WHERE variable = "OPACFineNoRenewals";
        }
        );

        say $out "Updated system preference 'OPACFineNoRenewals'";
    },
};
