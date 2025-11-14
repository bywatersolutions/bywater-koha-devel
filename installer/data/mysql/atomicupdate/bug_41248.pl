use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "41248",
    description => "Add index on background_jobs.data",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( index_exists( 'background_jobs', 'idx_data_255' ) ) {
            $dbh->do(
                q{
                ALTER TABLE background_jobs
                ADD INDEX idx_data_255 (data(255));
            }
            );

            say_success( $out, "Added index idx_data_255 for background_jobs.data" );
        } else {
            say_info( $out, "Index idx_data_255 for background_jobs.data already exists" );
        }
    }
};
