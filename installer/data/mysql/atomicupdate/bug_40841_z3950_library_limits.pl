use Modern::Perl;

return {
    bug_number  => "40841",
    description => "Add library limits support for Z39.50 servers",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        unless ( TableExists('z3950servers_branches') ) {
            $dbh->do(
                q{
                CREATE TABLE z3950servers_branches (
                  server_id int(11) NOT NULL COMMENT 'z3950server id',
                  branchcode varchar(10) NOT NULL COMMENT 'branch code',
                  PRIMARY KEY (server_id,branchcode),
                  KEY z3950servers_branches_ibfk_2 (branchcode),
                  CONSTRAINT z3950servers_branches_ibfk_1 FOREIGN KEY (server_id) REFERENCES z3950servers (id) ON DELETE CASCADE ON UPDATE CASCADE,
                  CONSTRAINT z3950servers_branches_ibfk_2 FOREIGN KEY (branchcode) REFERENCES branches (branchcode) ON DELETE CASCADE ON UPDATE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            }
            );
            say $out "Added z3950servers_branches table for library limits";
        }
    },
};
