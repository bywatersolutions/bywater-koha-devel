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

        say $out "Added new system preference 'ElasticsearchPatronSearch'";
    },
};
