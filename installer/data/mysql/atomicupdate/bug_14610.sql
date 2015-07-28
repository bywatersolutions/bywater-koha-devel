CREATE TABLE  `koha_kohaqa`.`article_requests` (
        `id` INT( 11 ) NOT NULL AUTO_INCREMENT PRIMARY KEY ,
        `borrowernumber` INT( 11 ) NOT NULL,
        `biblionumber` INT( 11 ) NOT NULL ,
        `itemnumber` INT NULL ,
        `title` TEXT NULL DEFAULT NULL ,
        `author` TEXT NULL DEFAULT NULL ,
        `volume` TEXT NULL DEFAULT NULL ,
        `issue` TEXT NULL DEFAULT NULL ,
        `date` TEXT NULL DEFAULT NULL ,
        `pages` TEXT NULL DEFAULT NULL ,
        `chapters` TEXT NULL DEFAULT NULL ,
        `created_on` TIMESTAMP NOT NULL ,
        `updated_on` TIMESTAMP NULL DEFAULT NULL ,
        INDEX (  `borrowernumber` ),
        INDEX (  `biblionumber` ),
        INDEX (  `itemnumber` )
        ) ENGINE = INNODB;

ALTER TABLE  `article_requests` ADD FOREIGN KEY (  `borrowernumber` ) REFERENCES  `koha_kohaqa`.`borrowers` (
        `borrowernumber`
        ) ON DELETE CASCADE ON UPDATE CASCADE ;

ALTER TABLE  `article_requests` ADD FOREIGN KEY (  `biblionumber` ) REFERENCES  `koha_kohaqa`.`biblio` (
        `biblionumber`
        ) ON DELETE CASCADE ON UPDATE CASCADE ;

ALTER TABLE  `article_requests` ADD FOREIGN KEY (  `itemnumber` ) REFERENCES  `koha_kohaqa`.`items` (
        `itemnumber`
        ) ON DELETE SET NULL ON UPDATE CASCADE ;
