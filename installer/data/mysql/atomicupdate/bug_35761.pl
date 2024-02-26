use Modern::Perl;

return {
    bug_number  => "35761",
    description => "Add an administration editor for FTP and SFTP servers",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        # Do you stuffs here
        $dbh->do(q{});


        $dbh->do(q{
            INSERT IGNORE INTO permissions
                (module_bit, code, description)
            VALUES ( 3, 'manage_ftp_servers', 'Manage FTP servers configuration');
        });

        # Print useful stuff here
        # tables
        say $out "Added new table 'XXX'";
    },
};
