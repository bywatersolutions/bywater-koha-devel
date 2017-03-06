$DBversion = 'XXX';  # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {

    $dbh->do(q{
        CREATE TABLE `circulation_rules` (
          `id` int(11) NOT NULL auto_increment,
          `branchcode` varchar(10) NULL default NULL,
          `categorycode` varchar(10) NULL default NULL,
          `itemtype` varchar(10) NULL default NULL,
          `rule_name` varchar(32) NOT NULL,
          `rule_value` varchar(32) NOT NULL,
          PRIMARY KEY (`id`),
          KEY `branchcode` (`branchcode`),
          KEY `categorycode` (`categorycode`),
          KEY `itemtype` (`itemtype`),
          UNIQUE (`branchcode`,`categorycode`,`itemtype`),
          CONSTRAINT `circulation_rules_ibfk_1` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`) ON DELETE CASCADE ON UPDATE CASCADE,
          CONSTRAINT `circulation_rules_ibfk_2` FOREIGN KEY (`categorycode`) REFERENCES `categories` (`categorycode`) ON DELETE CASCADE ON UPDATE CASCADE,
          CONSTRAINT `circulation_rules_ibfk_3` FOREIGN KEY (`itemtype`) REFERENCES `itemtypes` (`itemtype`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    });
    SetVersion( $DBversion );
    print "Upgrade to $DBversion done (Bug XXXXX - description)\n";
}
