use Modern::Perl;

return {
    bug_number  => "35267",
    description => "Enhance NoticeCSS preferences",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        my @new_prefs = qw(
            AllNoticeStylesheet
            AllNoticeCSS
            EmailNoticeCSS
            PrintNoticeStylesheet
            PrintNoticeCSS
            PrintSlipCSS
        );

        for my $pref (@new_prefs) {
            $dbh->do(
                q{INSERT IGNORE INTO systempreferences (variable, value) VALUES (?, '')},
                undef, $pref
                ) == 1
                && say $out "Added new system preference '$pref'";
        }

        $dbh->do(
            q{
            UPDATE systempreferences SET variable='EmailNoticeStylesheet' WHERE variable='NoticeCSS'
        }
        ) == 1 && say $out "Renamed system preference 'NoticeCSS' to 'EmailNoticeStylesheet'";

        $dbh->do(
            q{
            UPDATE systempreferences SET variable='PrintSlipStylesheet' WHERE variable='SlipCSS'
        }
        ) == 1 && say $out "Renamed system preference 'SlipCSS' to 'PrintSlipStylesheet'";

    },
};
