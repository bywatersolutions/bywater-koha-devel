$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    $dbh->do( "ALTER TABLE saved_sql ADD COLUMN combine_params tinyint(1) NOT NULL DEFAULT 0" );

    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug XXXXX - add combine params option to reports)\n";
}
