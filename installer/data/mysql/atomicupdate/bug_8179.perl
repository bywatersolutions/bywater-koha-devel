$DBversion = 'XXX'; # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    # you can use $dbh here like:
    $dbh->do( qq{
        INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
        ('AcqReceiveMultipleOrderLines', '0', NULL, 'Process multiple order lines at once', 'YesNo')
    });
    # or perform some test and warn
    # if( !column_exists( 'biblio', 'biblionumber' ) ) {
    #    warn "There is something wrong";
    # }

    # Always end with this (adjust the bug info)
    NewVersion( $DBversion, 8179, "Add AcqReceiveMultipleOrderLines system preference");
}
