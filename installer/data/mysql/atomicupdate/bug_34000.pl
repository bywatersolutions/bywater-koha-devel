use Modern::Perl;

return {
    bug_number => '34000',
    description => 'Add system preference autoMemberNumValue',
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (`variable`, `value`, `options`, `explanation`, `type`)
            VALUES ('autoMemberNumValue', '0', NULL, 'If autoMemberNum is enabled, Use this value for the next auto-generated cardnumber, then increment it.', 'Integer')
        });
    },
};
