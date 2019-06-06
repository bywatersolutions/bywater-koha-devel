$DBversion = 'XXX'; # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {

    # Add constraint for branchcode
    unless ( foreign_key_exists( 'issues', 'issues_ibfk_3' ) ) {
        $dbh->do(q{UPDATE issues i LEFT JOIN branches b ON (i.branchcode = b.branchcode) SET i.branchcode = NULL WHERE b.branchcode IS NULL});
        $dbh->do(q{ALTER TABLE issues ADD CONSTRAINT `issues_ibfk_3` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`) ON DELETE RESTRICT ON UPDATE CASCADE});
    }
    unless ( foreign_key_exists( 'old_issues', 'old_issues_ibfk_3' ) ) {
        $dbh->do(q{UPDATE old_issues i LEFT JOIN branches b ON (i.branchcode = b.branchcode) SET i.branchcode = NULL WHERE b.branchcode IS NULL});
        $dbh->do(q{ALTER TABLE old_issues ADD CONSTRAINT `old_issues_ibfk_3` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`) ON DELETE RESTRICT ON UPDATE CASCADE});
    }

    # Always end with this (adjust the bug info)
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 23066 - Add foreign key for issues tables to branches table for branchcodes)\n";
}
