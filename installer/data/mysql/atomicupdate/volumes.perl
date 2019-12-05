$DBversion = 'XXX'; # will be replaced by the RM
if ( CheckVersion( $DBversion ) ) {
    $dbh->do(q{
        INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
        ('EnableVolumes','0','','Enable volumes feature','YesNo');
    });

    unless ( TableExists('volumes') ) {
        $dbh->do(q{
            CREATE TABLE `volumes` ( -- information related to bibliographic records in Koha
            `id` int(11) NOT NULL auto_increment, -- primary key, unique identifier assigned by Koha
            `biblionumber` INT(11) NOT NULL default 0, -- foreign key linking this table to the biblio table
            `display_order` INT(4) NOT NULL default 0, -- specifies the 'sort order' for volumes
            `description` MEDIUMTEXT default NULL, -- equivilent to enumchron
            `created_on` TIMESTAMP NULL, -- Time and date the volume was created
            `updated_on` TIMESTAMP NOT NULL ON UPDATE CURRENT_TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- Time and date of the latest change on the volume (description)
            PRIMARY KEY  (`id`),
            CONSTRAINT `volumes_ibfk_1` FOREIGN KEY (`biblionumber`) REFERENCES `biblio` (`biblionumber`) ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    unless ( TableExists('volume_items') ) {
        $dbh->do(q{
            CREATE TABLE `volume_items` ( -- information related to bibliographic records in Koha
            `id` int(11) NOT NULL auto_increment, -- primary key, unique identifier assigned by Koha
            `volume_id` int(11) NOT NULL default 0, -- foreign key making this table a 1 to 1 join from items to volumes
            `itemnumber` int(11) NOT NULL default 0, -- foreign key linking this table to the items table
            PRIMARY KEY  (`id`),
            UNIQUE KEY (volume_id,itemnumber),
            CONSTRAINT `volume_items_iifk_1` FOREIGN KEY (`itemnumber`) REFERENCES `items` (`itemnumber`) ON DELETE CASCADE ON UPDATE CASCADE,
            CONSTRAINT `volume_items_vifk_1` FOREIGN KEY (`volume_id`) REFERENCES `volumes` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        });
    }

    # Always end with this (adjust the bug info)
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug XXXXX - Add ability to define volumes for items on a record)\n";
}
