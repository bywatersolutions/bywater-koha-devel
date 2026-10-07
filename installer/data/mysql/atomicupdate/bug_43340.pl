use Modern::Perl;
use Koha::Installer::Output qw(say_success say_failure);

return {
    bug_number  => "43340",
    description => "Add send_attempts and retry_after columns to message_queue",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( column_exists( 'message_queue', 'send_attempts' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE message_queue
                    ADD COLUMN send_attempts int(11) NOT NULL DEFAULT 0
                    COMMENT 'number of times a temporary failure prevented Koha from sending this message'
                    AFTER failure_code
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'message_queue.send_attempts'" );
            } else {
                say_failure( $out, "Failed to add column 'message_queue.send_attempts': " . $dbh->errstr );
            }
        }

        unless ( column_exists( 'message_queue', 'retry_after' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE message_queue
                    ADD COLUMN retry_after datetime DEFAULT NULL
                    COMMENT 'do not try to send this message again before this time'
                    AFTER send_attempts
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'message_queue.retry_after'" );
            } else {
                say_failure( $out, "Failed to add column 'message_queue.retry_after': " . $dbh->errstr );
            }
        }
    },
};
