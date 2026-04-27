use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success);

return {
    bug_number  => "34353",
    description => "Delete the SpineLabelShowPrintOnBibDetails syspref",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # If a columns_settings row already exists, OR the migrated value into
        # the existing is_hidden flag — when the previous syspref and an
        # existing table-settings override disagree we err on the side of
        # hiding the column (the old syspref's "Don't show" winning).
        for my $tablename (qw(holdings_table otherholdings_table)) {
            $dbh->do(
                q{INSERT INTO columns_settings
                           (module, page, tablename, columnname, cannot_be_toggled, is_hidden)
                       VALUES
                           ('catalogue', 'detail', ?, 'spinelabel', 0,
                            (SELECT COALESCE(
                                (SELECT NOT value FROM systempreferences WHERE variable='SpineLabelShowPrintOnBibDetails'),
                                0)))
                       ON DUPLICATE KEY UPDATE is_hidden=(is_hidden OR VALUES(is_hidden))},
                undef, $tablename
            );
        }

        my $deleted = $dbh->do(q{DELETE FROM systempreferences WHERE variable='SpineLabelShowPrintOnBibDetails'});

        if ( $deleted && $deleted > 0 ) {
            say_success( $out, "Deleted 'SpineLabelShowPrintOnBibDetails' syspref" );
        } else {
            say_warning( $out, "'SpineLabelShowPrintOnBibDetails' syspref already removed" );
        }
    },
};
