$DBversion = 'XXX';  # will be replaced by the RM

if( CheckVersion( $DBversion ) ) {
    $dbh->do( "ALTER TABLE import_biblios ADD COLUMN lccn varchar(25)" );
    $dbh->do( "ALTER TABLE import_biblios ADD COLUMN pubdate smallint(5)" );

    # Always end with this (adjust the bug info)
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug XXXXX - Add lccn and pubdate columns to import_biblios)\n";
}
