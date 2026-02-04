use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "41624",
    description => "Remove SeparateHoldingsByGroup system preference",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Check if the preference exists before removing
        my ($exists) = $dbh->selectrow_array(
            q{
                SELECT COUNT(*)
                FROM systempreferences
                WHERE variable = 'SeparateHoldingsByGroup'
            }
        );

        if ($exists) {
            $dbh->do(
                q{
                    DELETE FROM systempreferences
                    WHERE variable = 'SeparateHoldingsByGroup'
                }
            );
        }

        say_success( $out, "Removed system preference 'SeparateHoldingsByGroup'" );
    },
};
