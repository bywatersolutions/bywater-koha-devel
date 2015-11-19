-- Holds details for vendors supplying goods by EDI
CREATE TABLE IF NOT EXISTS `vendor_edi_accounts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `description` text NOT NULL,
  `host` varchar(40) DEFAULT NULL,
  `username` varchar(40) DEFAULT NULL,
  `password` varchar(40) DEFAULT NULL,
  `last_activity` date DEFAULT NULL,
  `vendor_id` int(11) DEFAULT NULL,
  `download_directory` text,
  `upload_directory` text,
  `san` varchar(20) DEFAULT NULL,
  `id_code_qualifier` varchar(3) DEFAULT '14',
  `transport` varchar(6) DEFAULT 'FTP',
  `quotes_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `invoices_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `orders_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `shipment_budget` int(11) DEFAULT NULL,
  `order_file_suffix` varchar(3) NOT NULL DEFAULT 'CEP',
  `quote_file_suffix` varchar(3) NOT NULL DEFAULT 'CEQ',
  `invoice_file_suffix` varchar(3) NOT NULL DEFAULT 'CEI',
  PRIMARY KEY (`id`),
  KEY `vendorid` (`vendor_id`),
  KEY `shipmentbudget` (`shipment_budget`),
  CONSTRAINT `vfk_shipment_budget` FOREIGN KEY (`shipment_budget`) REFERENCES `aqbudgets` (`budget_id`),
  CONSTRAINT `vfk_vendor_id` FOREIGN KEY (`vendor_id`) REFERENCES `aqbooksellers` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


-- Hold the actual edifact messages with links to associated baskets
CREATE TABLE IF NOT EXISTS edifact_messages (
  id int(11) NOT NULL auto_increment,
  message_type varchar(10) NOT NULL,
  transfer_date date,
  vendor_id int(11) references aqbooksellers( id ),
  edi_acct  integer references vendor_edi_accounts( id ),
  status text,
  basketno int(11) REFERENCES aqbasket( basketno),
  raw_msg mediumtext,
  filename text,
  deleted boolean not null default 0,
  PRIMARY KEY  (id),
  KEY vendorid ( vendor_id),
  KEY ediacct (edi_acct),
  KEY basketno ( basketno),
  CONSTRAINT emfk_vendor FOREIGN KEY ( vendor_id ) REFERENCES aqbooksellers ( id ),
  CONSTRAINT emfk_edi_acct FOREIGN KEY ( edi_acct ) REFERENCES vendor_edi_accounts ( id ),
  CONSTRAINT emfk_basketno FOREIGN KEY ( basketno ) REFERENCES aqbasket ( basketno )
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- invoices link back to the edifact message it was generated from
ALTER TABLE aqinvoices ADD COLUMN message_id INT(11) REFERENCES edifact_messages( id );

-- clean up link on deletes
ALTER TABLE aqinvoices ADD CONSTRAINT edifact_msg_fk FOREIGN KEY ( message_id ) REFERENCES edifact_messages ( id ) ON DELETE SET NULL;

-- Hold the supplier ids from quotes for ordering
-- although this is an EAN-13 article number the standard says 35 characters ???
ALTER TABLE aqorders ADD COLUMN line_item_id varchar(35);

-- The suppliers unique reference usually a quotation line number ('QLI')
-- Otherwise Suppliers unique orderline reference ('SLI')
ALTER TABLE aqorders ADD COLUMN suppliers_reference_number varchar(35);
ALTER TABLE aqorders ADD COLUMN suppliers_reference_qualifier varchar(3);

-- hold the EAN/SAN used in ordering
CREATE TABLE IF NOT EXISTS `edifact_ean` (
  `id` INT( 11 ) NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST,
  `branchcode` varchar(10) NOT NULL,
  `ean` varchar(15) NOT NULL,
  `id_code_qualifier` varchar(3) NOT NULL DEFAULT '14',
  KEY `branchcode` (`branchcode`),
  CONSTRAINT `edifact_ean_ibfk_1` FOREIGN KEY (`branchcode`) REFERENCES `branches` (`branchcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- Syspref budget to hold shipping costs
INSERT INTO systempreferences (variable, explanation, type) VALUES ('EDIInvoicesShippingBudget','The budget code used to allocate shipping charges to when processing EDI Invoice messages',  'free');

-- Add a permission for managing EDI
INSERT INTO permissions (module_bit, code, description) values (11, 'edi_manage', 'Manage EDIFACT transmissions');


