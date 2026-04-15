use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "21820",
    description =>
        "Add ElasticsearchEnableZebraQueue to disable / enable adding items to the zebra queue when using Elasticsearch",
    up => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value` ) VALUES
            ('ElasticsearchEnableZebraQueue', '1' )
        }
        );

        say $out "Added new system preference 'ElasticsearchEnableZebraQueue'";
    },
};
