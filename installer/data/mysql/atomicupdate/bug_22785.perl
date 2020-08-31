$DBversion = 'XXX';
if( CheckVersion( $DBversion ) ) {

    unless( column_exists('import_record_matches','chosen') ){
        $dbh->do( "ALTER TABLE import_record_matches ADD COLUMN chosen TINYINT null DEFAULT null AFTER score" );
    }
    NewVersion( $DBversion, 22785, "Add chosen column to miport_record_matches");
}
