use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "42406",
    description => "Split delete_reports into 'own' and 'all'",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            INSERT IGNORE INTO permissions (module_bit, code, description) VALUES
            ( 16, 'delete_own_reports', 'Delete SQL reports you have created'),
            ( 16, 'delete_all_reports', 'Delete SQL reports created by anyone')
        }
        );
        say $out "Added new permissions 'delete_own_reports' AND 'delete_all_reports'";

        $dbh->do(
            q{
            UPDATE user_permissions SET code = 'delete_all_reports' WHERE code = 'delete_reports'
        }
        );
        say $out "Update user_permission 'delete_reports' to 'delete_all_reports'";

        $dbh->do(
            q{
            DELETE FROM  permissions WHERE code = 'delete_reports'
        }
        );
        say $out "Removed permission 'delete_reports'";

    },
};
