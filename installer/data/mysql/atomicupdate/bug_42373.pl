use Modern::Perl;

return {
    bug_number  => "42373",
    description => "Add new system preference RESTMaxPatronsPageSize",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value` ) VALUES
            ('RESTMaxPatronsPageSize', '')
        }
        );

        say $out "Added new system preference 'RESTMaxPatronsPageSize'";
    },
};
