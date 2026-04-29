use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "39516",
    description => "Add composite_scores column to import_record_matches",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        if ( !column_exists( 'import_record_matches', 'composite_scores' ) ) {
            $dbh->do(
                q{
                ALTER TABLE import_record_matches
                ADD COLUMN `composite_scores` longtext DEFAULT NULL
                COMMENT 'JSON object mapping search_index to contributed score'
                AFTER `score`
            }
            );
            say $out "Added column 'import_record_matches.composite_scores'";
        }
    },
};
