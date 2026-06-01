use Modern::Perl;
use Koha::Installer::Output qw(say_success say_failure);

return {
    bug_number  => "36702",
    description => "Add retry columns to background_jobs so failed jobs can be retried up to a maximum number of tries",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( column_exists( 'background_jobs', 'max_retries' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE background_jobs
                        ADD COLUMN max_retries INT(11) DEFAULT NULL
                        COMMENT 'maximum number of times this job may be retried after a failure'
                        AFTER ended_on
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'background_jobs.max_retries'" );
            } else {
                say_failure( $out, "Failed to add column 'background_jobs.max_retries': " . $dbh->errstr );
            }
        }

        unless ( column_exists( 'background_jobs', 'retries' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE background_jobs
                        ADD COLUMN retries INT(11) NOT NULL DEFAULT 0
                        COMMENT 'number of times this job has already been retried, 0 for the original attempt'
                        AFTER max_retries
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'background_jobs.retries'" );
            } else {
                say_failure( $out, "Failed to add column 'background_jobs.retries': " . $dbh->errstr );
            }
        }

        unless ( column_exists( 'background_jobs', 'previous_job_id' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE background_jobs
                        ADD COLUMN previous_job_id INT(11) DEFAULT NULL
                        COMMENT 'the job this job is a retry of, if any'
                        AFTER retries,
                        ADD KEY previous_job_id (previous_job_id)
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'background_jobs.previous_job_id'" );
            } else {
                say_failure( $out, "Failed to add column 'background_jobs.previous_job_id': " . $dbh->errstr );
            }
        }

        unless ( column_exists( 'background_jobs', 'not_before' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE background_jobs
                        ADD COLUMN not_before DATETIME DEFAULT NULL
                        COMMENT 'the job should not be processed before this time, used for the retry cooldown'
                        AFTER previous_job_id
                }
            );
            if ($ok) {
                say_success( $out, "Added column 'background_jobs.not_before'" );
            } else {
                say_failure( $out, "Failed to add column 'background_jobs.not_before': " . $dbh->errstr );
            }
        }

        unless ( foreign_key_exists( 'background_jobs', 'background_jobs_ibfk_1' ) ) {
            my $ok = $dbh->do(
                q{
                    ALTER TABLE background_jobs
                        ADD CONSTRAINT background_jobs_ibfk_1
                          FOREIGN KEY (previous_job_id) REFERENCES background_jobs (id)
                          ON DELETE SET NULL ON UPDATE CASCADE
                }
            );
            if ($ok) {
                say_success( $out, "Added foreign key 'background_jobs.previous_job_id' -> 'background_jobs.id'" );
            } else {
                say_failure( $out, "Failed to add foreign key on 'background_jobs.previous_job_id': " . $dbh->errstr );
            }
        }

        unless (
            $dbh->selectrow_array(
                q{ SELECT COUNT(*) FROM systempreferences WHERE variable = 'BackgroundJobsDefaultMaxRetries' })
            )
        {
            my $ok = $dbh->do(
                q{
                    INSERT IGNORE INTO systempreferences ( variable, value )
                        VALUES ( 'BackgroundJobsDefaultMaxRetries', '3' )
                }
            );
            if ($ok) {
                say_success( $out, "Added system preference 'BackgroundJobsDefaultMaxRetries'" );
            } else {
                say_failure(
                    $out,
                    "Failed to add system preference 'BackgroundJobsDefaultMaxRetries': " . $dbh->errstr
                );
            }
        }

        unless (
            $dbh->selectrow_array(
                q{ SELECT COUNT(*) FROM systempreferences WHERE variable = 'BackgroundJobsRetryDelay' })
            )
        {
            my $ok = $dbh->do(
                q{
                    INSERT IGNORE INTO systempreferences ( variable, value )
                        VALUES ( 'BackgroundJobsRetryDelay', '30' )
                }
            );
            if ($ok) {
                say_success( $out, "Added system preference 'BackgroundJobsRetryDelay'" );
            } else {
                say_failure( $out, "Failed to add system preference 'BackgroundJobsRetryDelay': " . $dbh->errstr );
            }
        }
    },
};
