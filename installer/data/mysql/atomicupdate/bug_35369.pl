use Modern::Perl;

return {
    bug_number  => "BUG_NUMBER",
    description => "A single line description",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
            ('SIP2ScreenMessageGreeting','Greetings from Koha. ','','SIP greetings message that will being each SIP AF field','Free')
        });

        say $out "Added new system preference 'SIP2ScreenMessageGreeting'";
    },
};
