use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "34962",
    description => "Add system_messages table and the view_system_messages and manage_system_messages permissions",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        if ( TableExists('system_messages') ) {
            say_info( $out, "Table 'system_messages' already exists" );
        } else {
            my $rv = $dbh->do(
                q{
                    CREATE TABLE `system_messages` (
                    `system_message_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'primary key',
                    `component` varchar(80) NOT NULL COMMENT 'area of Koha that reported the message',
                    `message` mediumtext NOT NULL COMMENT 'message text',
                    `occurrences` int(11) NOT NULL DEFAULT 1 COMMENT 'number of times this message has been reported since it was first seen',
                    `created_date` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'when this message was first reported',
                    `updated_date` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'when this message was last reported',
                    `cleared_date` datetime DEFAULT NULL COMMENT 'when this message was cleared, NULL while it is still showing',
                    PRIMARY KEY (`system_message_id`),
                    KEY `system_messages_cleared_date_idx` (`cleared_date`)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                }
            );
            if ($rv) {
                say_success( $out, "Added new table 'system_messages'" );
            } else {
                say_warning( $out, "Failed to add table 'system_messages': " . $dbh->errstr );
            }
        }

        for my $permission (
            [ 'view_system_messages',   'View system messages' ],
            [ 'manage_system_messages', 'Manage system messages' ]
            )
        {
            my ( $code, $description ) = @$permission;
            my $rv = $dbh->do(
                q{
                    INSERT IGNORE INTO permissions (module_bit, code, description)
                    VALUES (3, ?, ?)
                },
                undef, $code, $description
            );
            if ( $rv && $rv > 0 ) {
                say_success( $out, "Added new permission '$code'" );
            } elsif ( defined $rv ) {
                say_info( $out, "Permission '$code' already exists" );
            } else {
                say_warning( $out, "Failed to add permission '$code': " . $dbh->errstr );
            }
        }
    },
};
