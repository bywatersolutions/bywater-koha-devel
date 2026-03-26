use Modern::Perl;

return {
    bug_number  => "35267",
    description => "Enhance NoticeCSS preferences",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Do you stuffs here
        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value) VALUES
            ('AllNoticeStylesheet', ''),
            ('AllNoticeCSS',''),
            ('EmailNoticeCSS',''),
            ('PrintNoticeCSS',''),
            ('PrintSlipCSS','')
        }
        );
        say $out "Added new system preference 'AllNoticeStylesheet'";
        say $out "Added new system preference 'AllNoticeCSS'";
        say $out "Added new system preference 'EmailNoticeCSS'";
        say $out "Added new system preference 'PrintNoticeCSS'";
        say $out "Added new system preference 'PrintSlipCSS'";

        $dbh->do(
            q{
            UPDATE systempreferences SET variable='EmailNoticeStylesheet' WHERE variable='NoticeCSS'
        }
        );
        say $out "Rename system preference 'NoticeCSS' to 'EmailNoticeStylesheet'";

        $dbh->do(
            q{
            UPDATE systempreferences SET variable='PrintSlipStylesheet' WHERE variable='SlipCSS'
        }
        );
        say $out "Rename system preference 'SlipCSS' to 'PrintSlipStylesheet'";

    },
};
