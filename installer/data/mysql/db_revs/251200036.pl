use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "40853",
    description =>
        "Add ElasticsearchBoostFieldMatchAmount to allow for increasing the weight of the additional field boost search",
    up => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO systempreferences ( `variable`, `value` ) VALUES
            ('ElasticsearchBoostFieldMatchAmount', '0' )
        }
        );

        say $out "Added new system preference 'ElasticsearchBoostFieldMatchAmount'";
    },
};
