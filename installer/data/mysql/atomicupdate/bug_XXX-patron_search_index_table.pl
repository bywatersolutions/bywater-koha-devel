use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "XXX",
    description => "Add patron_search_index denormalized table for Database patron search backend",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( TableExists('patron_search_index') ) {
            $dbh->do(q{
                CREATE TABLE patron_search_index (
                    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    patron_id       INT NOT NULL,
                    field_group     VARCHAR(80) NOT NULL,
                    content         MEDIUMTEXT NOT NULL,
                    PRIMARY KEY (id),
                    INDEX idx_psi_patron (patron_id),
                    INDEX idx_psi_group_patron (field_group, patron_id),
                    FULLTEXT INDEX idx_psi_ft (content)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            });
            say $out "Created patron_search_index table";
        }
    },
};
