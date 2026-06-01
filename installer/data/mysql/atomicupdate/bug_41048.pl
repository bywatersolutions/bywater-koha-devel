use Modern::Perl;
use Koha::Installer::Output qw(say_success say_failure);

return {
    bug_number  => "41048",
    description => "Add ability to disallow empty patron searches",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        my $ok = $dbh->do(
            q{
INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
('EmptyPatronSearches','1',NULL,'If disabled, patron searches performed without any search criteria are rejected, both in the staff interface and via the REST API.','YesNo')
            }
        );

        if ($ok) {
            say_success( $out, "Added new system preference 'EmptyPatronSearches'" );
        } else {
            say_failure( $out, "Failed to add system preference 'EmptyPatronSearches': " . $dbh->errstr );
        }
    },
};
