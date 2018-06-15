CREATE TABLE `return_claims` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `borrowernumber` int(11) DEFAULT NULL,
  `issue_id` int(11) DEFAULT NULL,
  `itemnumber` int(11) DEFAULT NULL,
  `biblionumber` int(11) DEFAULT NULL,
  `notes` text,
  `resolution` varchar(80) DEFAULT NULL,
  `created_on` TIMESTAMP NULL,
  `updated_on` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `borrowernumber` (`borrowernumber`),
  KEY `itemnumber` (`itemnumber`),
  KEY `biblionumber` (`biblionumber`),
  CONSTRAINT `return_claims_ibfk_3` FOREIGN KEY (`biblionumber`) REFERENCES `biblio` (`biblionumber`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `return_claims_ibfk_1` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `return_claims_ibfk_2` FOREIGN KEY (`itemnumber`) REFERENCES `items` (`itemnumber`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO authorised_values ( category, authorised_value, lib )
SELECT 'LOST', authorised_value + 1, 'Claims returned'
FROM authorised_values WHERE category = 'LOST' ORDER BY authorised_value DESC LIMIT 1;

INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` )
SELECT 'ClaimsReturnedLostAV', authorised_value, '', 'The AV LOST value that represents a return claim', 'free'
FROM authorised_values WHERE category = 'LOST' ORDER BY authorised_value DESC LIMIT 1;

INSERT IGNORE INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
('ClaimsReturnedAlertThreshold', '', '', 'Number of claims at which to alert staff during checkout', 'Integer'),
('ClaimsReturnedAlertType', 'open', 'unresolved|all', 'Count only open claims or all for claims alert at chckout', 'Choice'),
('ClaimsReturnedLostCharge', 'ask', 'charge|ask|no_charge', 'Controls how patron is charged for return claims', 'Choice');

INSERT IGNORE INTO authorised_value_categories ( category_name ) VALUES ( 'RETURN_CLAIM_RESOLUTION' );

INSERT IGNORE INTO authorised_values ( category, authorised_value, lib ) VALUES
( 'RETURN_CLAIM_RESOLUTION', 'RETURNED_BY_PATRON', 'Returned by patron' ),
( 'RETURN_CLAIM_RESOLUTION', 'FOUND_IN_LIBRARY', 'Found in library' );
