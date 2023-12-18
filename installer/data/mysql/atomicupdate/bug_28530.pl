use Modern::Perl;

return {
    bug_number  => "28530",
    description => "Add library float limits",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(
            q{
            ALTER TABLE branchtransfers MODIFY COLUMN `reason` enum('Manual','StockrotationAdvance','StockrotationRepatriation','ReturnToHome','ReturnToHolding','RotatingCollection','Reserve','LostReserve','CancelReserve','TransferCancellation','Recall','RecallCancellation', 'LibraryFloatLimit') DEFAULT NULL COMMENT 'what triggered the transfer'
        }
        );

        $dbh->do(
            q{
                INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
                ('UseLibraryFloatLimits', '0', '', 'Enables library float limits', 'YesNo');
            }
        );
        say $out "Added new system preference 'UseLibraryFloatLimits'";

        unless ( TableExists('library_float_limits') ) {
            $dbh->do(
                q{
                CREATE TABLE `library_float_limits` (
                `branchcode` varchar(10) NOT NULL,
                `itemtype` varchar(10) NOT NULL,
                `float_limit` int(11) NULL DEFAULT NULL,
                PRIMARY KEY (`branchcode`,`itemtype`),
                CONSTRAINT `library_float_limits_ibfk_bc` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`) ON DELETE CASCADE ON UPDATE CASCADE,
                CONSTRAINT `library_float_limits_ibfk_it` FOREIGN KEY (`itemtype`) REFERENCES `itemtypes` (`itemtype`) ON DELETE CASCADE ON UPDATE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            }
            );
        }
        say $out "Added new table 'library_float_limits'";
    },
};
