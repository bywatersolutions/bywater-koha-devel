$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {

    if( column_exists( 'reserves', 'reservedate' ) ) {
        $dbh->do(q{ALTER TABLE reserves MODIFY column reservedate datetime});
    }

    if( column_exists( 'reserves', 'expirationdate' ) ) {
        $dbh->do(q{ALTER TABLE reserves MODIFY column expirationdate datetime});
    }

    # Always end with this (adjust the bug info)
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 24718 - Use datetime for reserves.reservedate and reserves.expirationdate)\n";
}
