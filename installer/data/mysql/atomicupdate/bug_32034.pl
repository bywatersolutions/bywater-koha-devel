use Modern::Perl;

return {
    bug_number => "32034",
    description => "Library branch transfers should be in the action logs",
    up => sub {
        my ($args) = @_;
        my $dbh = $args->{dbh};

        $dbh->do( q{
            INSERT IGNORE INTO systempreferences (variable, value, explanation, options, type)
            VALUES ('TransfersLog', '0', 'If enabled, log item transfer changes', '', 'YesNo')
        });
    },
}
