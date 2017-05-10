$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    $dbh->do(q{
        UPDATE systempreferences SET variable = 'WaitingHoldCancelationFee' WHERE variable = 'ExpireReservesMaxPickUpDelayCharge';
    });

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 14137 - Allow ExpireReservesMaxPickUpDelayCharge to be used without ExpireReservesMaxPickUpDelay)\n";
}
