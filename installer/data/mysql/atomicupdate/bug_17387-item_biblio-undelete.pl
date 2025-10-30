use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "17387",
    description => "Add records_restore permission",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO permissions (module_bit, code, description)
            VALUES (13, 'records_restore', 'Restore deleted records')
        }
        );

        say_success( $out, "Added new permission 'tools:records_restore'" );

    },
};
