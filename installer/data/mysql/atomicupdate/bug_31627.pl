use Modern::Perl;

return {
    bug_number => "31627",
    description => "Add syspref SendLetterIdInEmailNotices",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};
        $dbh->do(q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
            ('SendLetterIdInEmailNotices','0',NULL,'Add template id to bottom of emailed notices','YesNo')
        });
    },
};
