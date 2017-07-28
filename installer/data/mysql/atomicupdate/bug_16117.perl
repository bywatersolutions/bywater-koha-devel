$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    $dbh->do(q{
        INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
        ('LogInvalidItems','0','','Log scanned invalid item identifiers as statistics','YesNo'),
        ('LogInvalidPatrons','0','','Log scanned invalid patron identifiers as statistics','YesNo');
    });

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug 16117 - Feature request: Log borrower cardnumbers and item barcodes which are not valid)\n";
}
