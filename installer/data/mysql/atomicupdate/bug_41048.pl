use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "41048",
    description => ":dd ability to disallow empty patron searches",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
('DisallowEmptyPatronSearches','0',NULL,'If enabled, the Patron REST API will return a 422 status code when a search is performed without any criteria.','YesNo')
        }
        );

        say $out "Added new system preference 'DisallowEmptyPatronSearches'";
    },
};
