use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "XXX",
    description => "Add ElasticsearchPatronSearch system preference",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('ElasticsearchPatronSearch', '0', NULL, 'Use Elasticsearch for patron searches', 'YesNo')
        });

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('ElasticsearchIndexStatus_patrons', '0', NULL, 'Elasticsearch patrons index status', 'integer')
        });

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
            VALUES ('ElasticsearchPatronMaxResultWindow', '1000000', NULL, 'Maximum result window (from + size) for the Elasticsearch patrons index. Applied at index creation time.', 'integer')
        });

        say $out "Added new system preference 'ElasticsearchPatronSearch'";
        say $out "Added new system preference 'ElasticsearchIndexStatus_patrons'";
        say $out "Added new system preference 'ElasticsearchPatronMaxResultWindow'";
    },
};
