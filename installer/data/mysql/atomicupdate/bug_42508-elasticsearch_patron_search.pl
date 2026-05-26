use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "42508",
    description => "Add system preferences for Elasticsearch patron search",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value)
            VALUES ('ElasticsearchPatronSearch', '0')
        }
        );

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value)
            VALUES ('ElasticsearchIndexStatus_patrons', '0')
        }
        );

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences (variable, value)
            VALUES ('ElasticsearchPatronMaxResultWindow', '1000000')
        }
        );

        say $out "Added new system preference 'ElasticsearchPatronSearch'";
        say $out "Added new system preference 'ElasticsearchIndexStatus_patrons'";
        say $out "Added new system preference 'ElasticsearchPatronMaxResultWindow'";
    },
};
