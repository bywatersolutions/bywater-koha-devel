use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_failure say_success say_info);

return {
    bug_number  => "32773",
    description => "Add ability to have more than 1 Fast add framework",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        if ( !column_exists( 'biblio_framework', 'is_fast_add' ) ) {
            $dbh->do(
                q{
                ALTER TABLE biblio_framework
                ADD COLUMN is_fast_add TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'the ability to be used as a Fast add framework'
                AFTER frameworktext;
            }
            );
            say_success( $out, "Added column 'biblio_framework.is_fast_add'" );
            $dbh->do(
                q{
                UPDATE biblio_framework SET is_fast_add = 1 where frameworkcode = 'FA';
            }
            );
            say_success( $out, "Set is_fast_add = 1 for FA framework'" );
        } else {
            say_info( $out, "Column 'biblio_framework.is_fast_add' already exists!" );
        }
    },
};
