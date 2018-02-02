INSERT INTO systempreferences ( `variable`, `value`, `options`, `explanation`, `type` ) VALUES
('ExpireReservesAutoFill','0',NULL,'Automatically fill the next hold with a automatically canceled expired waiting hold.','YesNo'),
('ExpireReservesAutoFillEmail','', NULL,'If ExpireReservesAutoFill and an email is defined here, the email notification for the change in the hold will be sent to this address.','Free');

INSERT INTO letter(module,code,branchcode,name,is_html,title,content,message_transport_type)
VALUES ( 'reserves', 'HOLD_CHANGED', '', 'Canceled Hold Available for Different Patron', '0', 'Canceled Hold Available for Different Patron', 'The patron picking up <<biblio.title>> (<<items.barcode>>) has changed to <<borrowers.firstname>> <<borrowers.surname>> (<<borrowers.cardnumber>>).

Please update the hold information for this item.

Title: <<biblio.title>>
Author: <<biblio.author>>
Copy: <<items.copynumber>>
Pickup location: <<branches.branchname>>', 'email');
