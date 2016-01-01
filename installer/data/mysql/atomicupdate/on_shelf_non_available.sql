ALTER TABLE issuingrules ADD COLUMN allow_hold_if_items_available TINYINT(1) NOT NULL DEFAULT 1 AFTER opacitemholds;
