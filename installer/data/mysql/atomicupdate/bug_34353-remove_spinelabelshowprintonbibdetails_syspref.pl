use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "34353",
    description => "Delete the SpineLabelShowPrintOnBibDetails syspref",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        for my $tablename (qw(holdings_table otherholdings_table)) {
            $dbh->do(
                q{INSERT INTO columns_settings
                           (module, page, tablename, columnname, cannot_be_toggled, is_hidden)
                       VALUES
                           ('catalogue', 'detail', ?, 'spinelabel', 0,
                            (SELECT IFNULL(
                                (SELECT NOT value FROM systempreferences WHERE variable='SpineLabelShowPrintOnBibDetails'),
                                0)))
                       ON DUPLICATE KEY UPDATE is_hidden=(is_hidden OR VALUES(is_hidden))},
                undef, $tablename
            );
        }

        $dbh->do(q{DELETE FROM systempreferences WHERE variable='SpineLabelShowPrintOnBibDetails'});

        say_success( $out, "Deleted 'SpineLabelShowPrintOnBibDetails' syspref" );
    },
};
