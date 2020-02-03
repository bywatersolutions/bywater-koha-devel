$DBversion = 'XXX';
if( CheckVersion( $DBversion ) ) {
    $dbh->do(q{INSERT IGNORE INTO systempreferences (variable,value,explanation,options,type) VALUES ('HourBasedHolds', 0, 'Allow holds to operate on an hourly or minutes basis', NULL, 'YesNo') });

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 24718 - Add HourBasedHolds system preference)\n";
}
