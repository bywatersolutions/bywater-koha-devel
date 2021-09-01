use Modern::Perl;

return {
    bug_number => "22866",
    description => "Add new syspref AllowRenewalItemsDeniedOverride",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable,value,explanation,options,type) VALUES
            ('AllowRenewalItemsDeniedOverride','0','','If ON, allow items on hold to be renewed by staff even if disallowed by ItemsDeniedRenewal','YesNo');
        });
    },
}
