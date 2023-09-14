use Modern::Perl;

return {
    bug_number  => "34784",
    description => "Add ability to populate empty item callnumbers for a record based on the itemcallnumber syspref",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` )
            VALUES ('EnablePopulateCallnumbers','0','','Enable populate callnumber feature','YesNo')
        }
        );

        say $out "Added new system preference 'EnablePopulateCallnumbers'";
    },
};
