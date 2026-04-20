use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "23909",
    description => "Distinguish pending and waiting holds at checkout",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        for my $pref (qw(AllowItemsOnHoldCheckoutSCO AllowItemsOnHoldCheckoutSIP)) {
            my ($type) = $dbh->selectrow_array(
                q{SELECT type FROM systempreferences WHERE variable = ?},
                undef, $pref,
            );

            if ( $type && $type eq 'Choice' ) {
                say_warning( $out, "System preference '$pref' already migrated to Choice, skipping" );
                next;
            }

            $dbh->do(
                q{
                    UPDATE systempreferences
                    SET type = 'Choice', options = '0|1|2'
                    WHERE variable = ?
                },
                undef, $pref,
            );
            say $out "Updated system preference '$pref' to Choice (0|1|2)";
            say_info(
                $out,
                "If '$pref' was previously set to 'Allow' (1) and you want to continue allowing "
                    . "checkout of waiting holds, change it to 'Allow pending and waiting' (2). "
                    . "Value 1 now means 'Allow pending only'."
            );
        }

        my $rv = $dbh->do(
            q{
                INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type)
                VALUES (
                    'AllowHoldCheckoutOverride',
                    '1',
                    NULL,
                    'Allow staff to override and check out items that are on hold for another patron',
                    'YesNo'
                )
            }
        );

        if ( $rv && $rv > 0 ) {
            say_success( $out, "Added new system preference 'AllowHoldCheckoutOverride'" );
        } else {
            say_warning( $out, "System preference 'AllowHoldCheckoutOverride' already exists, skipping" );
        }
    },
};
