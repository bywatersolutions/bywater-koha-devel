CREATE TABLE `borrower_relationships` (
      id INT(11) NOT NULL AUTO_INCREMENT,
      guarantor_id INT(11) NULL DEFAULT NULL,
      guarantee_id INT(11) NOT NULL,
      relationship VARCHAR(100) COLLATE utf8_unicode_ci NOT NULL,
      PRIMARY KEY (id),
      CONSTRAINT r_guarantor FOREIGN KEY ( guarantor_id ) REFERENCES borrowers ( borrowernumber ) ON UPDATE CASCADE ON DELETE CASCADE,
      CONSTRAINT r_guarantee FOREIGN KEY ( guarantee_id ) REFERENCES borrowers ( borrowernumber ) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

UPDATE borrowers LEFT JOIN borrowers guarantor ON ( borrowers.guarantorid = guarantor.borrowernumber ) SET borrowers.guarantorid = NULL WHERE guarantor.borrowernumber IS NULL;

INSERT INTO borrower_relationships ( guarantor_id, guarantee_id, relationship ) SELECT guarantorid, borrowernumber, relationship FROM borrowers WHERE guarantorid IS NOT NULL;

ALTER TABLE borrowers DROP guarantorid;
ALTER TABLE deletedborrowers DROP guarantorid;
ALTER TABLE borrowermodification DROP guarantorid;
