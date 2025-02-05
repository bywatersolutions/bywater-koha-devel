use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "BUG_NUMBER",
    description => "A single line description",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
            ('ElasticsearchIncludeDocType', '0', '', 'When displaying ES records on the details page include the "type => _doc".', 'YesNo')
        }
        );

        # sysprefs
        say $out "Added new system preference 'ElasticsearchIncludeDocType'";
    },
};
