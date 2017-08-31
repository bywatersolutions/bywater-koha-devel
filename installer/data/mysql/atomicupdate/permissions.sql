ALTER TABLE user_permissions
    DROP FOREIGN KEY user_permissions_ibfk_2,
    DROP index user_permissions_ibfk_2,
    DROP COLUMN module_bit;

ALTER TABLE permissions
    DROP PRIMARY KEY,
    DROP FOREIGN KEY permissions_ibfk_1,
    ADD PRIMARY KEY ( code ),
    ADD COLUMN `parent` VARCHAR(64) NULL DEFAULT NULL FIRST,
    ADD KEY parent ( parent );

ALTER TABLE permissions ADD FOREIGN KEY ( parent ) REFERENCES permissions ( code );

ALTER TABLE user_permissions ADD CONSTRAINT user_permissions_ibfk_2 FOREIGN KEY (code) REFERENCES permissions(code);

INSERT INTO permissions ( parent, code, description ) VALUES ( NULL, 'superlibrarian', 'Access to all librarian functions' );

INSERT INTO permissions ( parent, code, description )
SELECT 'superlibrarian', flag, flagdesc FROM userflags
 WHERE flag != 'superlibrarian';

UPDATE permissions LEFT JOIN userflags ON ( userflags.bit = permissions.module_bit ) SET parent = flag WHERE flag != 'superlibrarian';

INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'superlibrarian'   FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -1, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'circulate'        FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -2, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'catalogue'        FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -3, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'parameters'       FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -4, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'borrowers'        FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -5, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'permissions'      FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -6, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'reserveforothers' FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -7, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'editcatalogue'    FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -8, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'updatecharges'    FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ),  -9, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'acquisition'      FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -10, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'management'       FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -11, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'tools'            FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -12, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'editauthorities'  FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -13, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'serials'          FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -14, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'reports'          FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -15, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'staffaccess'      FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -16, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'coursereserves'   FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -17, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'plugins'          FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -18, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'lists'            FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -19, 1 ) = '1';
INSERT INTO user_permissions ( borrowernumber, code ) SELECT borrowernumber, 'clubs'            FROM borrowers WHERE  substring( lpad( conv( borrowers.flags, 10, 2 ), 21, '0' ), -20, 1 ) = '1';

ALTER TABLE permissions DROP COLUMN module_bit;

ALTER TABLE borrowers DROP COLUMN flags;

DROP TABLE userflags;
