describe("Circulation - FineNoRenewals and AllowFineOverrideRenewing", () => {
    beforeEach(() => {
        cy.login();
        cy.title().should("eq", "Koha staff interface");
    });

    describe("Renewal with fines", () => {
        let patron, checkout, fine_amount;

        beforeEach(function () {
            // Set up test data: patron with checkout and fines
            cy.task("insertSampleCheckout").then(objects => {
                patron = objects.patron;
                checkout = objects.checkout;

                // Disable auto_renew on the checkout to get too_much_owing error instead of auto_too_much_owing
                cy.task("query", {
                    sql: "UPDATE issues SET auto_renew = 0 WHERE issue_id = ?",
                    values: [checkout.checkout_id],
                });

                // Set FineNoRenewals to 5
                cy.set_syspref("FineNoRenewals", "5");

                // Add a fine of 10 to the patron (exceeds limit)
                fine_amount = 10;
                cy.task("query", {
                    sql: `INSERT INTO accountlines (borrowernumber, amountoutstanding, debit_type_code, status, interface, itemnumber)
                          VALUES (?, ?, 'OVERDUE', 'UNRETURNED', 'test', ?)`,
                    values: [
                        patron.patron_id,
                        fine_amount,
                        objects.items[0].item_id,
                    ],
                });

                cy.wrap(objects).as("testObjects");
            });
        });

        afterEach(function () {
            // Clean up
            cy.task("deleteSampleObjects", [this.testObjects]);

            // Reset system preferences
            cy.set_syspref("FineNoRenewals", "100");
            cy.set_syspref("AllowFineOverrideRenewing", "0");
        });

        it("should block renewal when patron has fines over FineNoRenewals limit", function () {
            const barcode = this.testObjects.items[0].external_id;

            // Visit renewal page
            cy.visit("/cgi-bin/koha/circ/renew.pl");

            // Enter barcode
            cy.get("#barcode").type(barcode);
            cy.get("#barcode").closest("form").submit();

            // Should see error message about patron debt
            cy.get(".dialog.alert").should("be.visible");
            cy.get(".dialog.alert li").should(
                "contain",
                `The patron has a debt of`
            );
        });

        it("should show override button when AllowFineOverrideRenewing is enabled", function () {
            // Enable AllowFineOverrideRenewing
            cy.set_syspref("AllowFineOverrideRenewing", "1");

            const barcode = this.testObjects.items[0].external_id;

            // Visit renewal page
            cy.visit("/cgi-bin/koha/circ/renew.pl");

            // Enter barcode
            cy.get("#barcode").type(barcode);
            cy.get("#barcode").closest("form").submit();

            // Should see error message about patron debt
            cy.get(".dialog.alert").should("be.visible");

            cy.get(".dialog.alert li").should(
                "contain",
                `The patron has a debt of`
            );

            // Should see override button
            cy.get('.dialog.alert form button[type="submit"].approve').should(
                "be.visible"
            );
            cy.get('.dialog.alert form button[type="submit"].approve').should(
                "contain",
                "Override and renew"
            );
        });

        it("should NOT show override button when AllowFineOverrideRenewing is disabled", function () {
            // Ensure AllowFineOverrideRenewing is disabled
            cy.set_syspref("AllowFineOverrideRenewing", "0");

            const barcode = this.testObjects.items[0].external_id;

            // Visit renewal page
            cy.visit("/cgi-bin/koha/circ/renew.pl");

            // Enter barcode
            cy.get("#barcode").type(barcode);
            cy.get("#barcode").closest("form").submit();

            // Should see error message about patron debt
            cy.get(".dialog.alert").should("be.visible");
            cy.get(".dialog.alert li").should(
                "contain",
                `The patron has a debt of`
            );

            // Should NOT see override button
            cy.get('.dialog.alert form button[type="submit"].approve').should(
                "not.exist"
            );
        });

        it("should allow renewal after override when AllowFineOverrideRenewing is enabled", function () {
            // Enable AllowFineOverrideRenewing
            cy.set_syspref("AllowFineOverrideRenewing", "1");

            const barcode = this.testObjects.items[0].external_id;

            // Visit renewal page
            cy.visit("/cgi-bin/koha/circ/renew.pl");

            // Enter barcode
            cy.get("#barcode").type(barcode);
            cy.get("#barcode").closest("form").submit();

            // Click override button
            cy.get('.dialog.alert form button[type="submit"].approve').click();

            // Should see success message
            cy.get(".dialog.message").should("be.visible");
            cy.get(".dialog.message").should("contain", "Item renewed");
        });

        it("should allow renewal when patron has fines below FineNoRenewals limit", function () {
            // Delete the existing fine
            cy.task("query", {
                sql: "DELETE FROM accountlines WHERE borrowernumber = ?",
                values: [patron.patron_id],
            });

            // Add a smaller fine (below limit)
            cy.task("query", {
                sql: `INSERT INTO accountlines (borrowernumber, amountoutstanding, debit_type_code, status, interface, itemnumber)
                      VALUES (?, 3.00, 'OVERDUE', 'UNRETURNED', 'test', ?)`,
                values: [patron.patron_id, this.testObjects.items[0].item_id],
            });

            const barcode = this.testObjects.items[0].external_id;

            // Visit renewal page
            cy.visit("/cgi-bin/koha/circ/renew.pl");

            // Enter barcode
            cy.get("#barcode").type(barcode);
            cy.get("#barcode").closest("form").submit();

            // Should see success message (no error about fines)
            cy.get(".dialog.message").should("be.visible");
            cy.get(".dialog.message").should("contain", "Item renewed");
        });
    });
});
