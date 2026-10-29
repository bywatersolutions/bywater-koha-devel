// End-to-end tests for the Vue check-in page (circ/checkin.pl).
//
// The data is created in the database through the plugin tasks and the
// outcome of each action is checked in the database too, so these tests
// exercise the page, the REST API and the circulation code together.

// The library the 'koha' user is logged in at
const LOGGED_IN_LIBRARY = "CPL";

// System preferences these tests depend on, and the value each test starts
// with. The original values are restored after each test.
const PREFS = {
    AutomaticItemReturn: "1",
    AutomaticConfirmTransfer: "0",
    BlockReturnOfLostItems: "0",
    BlockReturnOfWithdrawnItems: "1",
    HoldsAutoFill: "0",
    SpecifyReturnDate: "1",
    TransfersBlockCirc: "0",
    UseRecalls: "off",
};

const originalPrefs = {};

// Objects to remove after each test, and SQL statements to run before
// they are removed
let cleanupObjects = [];
let cleanupQueries = [];

function cleanupLater(objects) {
    cleanupObjects.push(objects);
}

function cleanupQueryLater(sql, values) {
    cleanupQueries.push({ sql, values });
}

function dbQuery(sql, values = []) {
    return cy.task("query", { sql, values });
}

// Move an item to a library, so it does not need to be transferred when
// it is checked in there
function moveItemTo(item, library_id) {
    return dbQuery(
        "UPDATE items SET homebranch=?, holdingbranch=? WHERE itemnumber=?",
        [library_id, library_id, item.item_id]
    );
}

// Create a checked out item. Its home library is LOGGED_IN_LIBRARY unless
// stay_home is set, in which case it stays at a newly created library.
function createCheckout({ stay_home = false } = {}) {
    return cy.task("insertSampleCheckout").then(objects => {
        cleanupLater(objects);
        cleanupLater({
            category: { patron_category_id: objects.patron.category_id },
        });
        const item = objects.items[0];
        cleanupItemHistory(item);
        if (stay_home) {
            return cy.wrap(objects);
        }
        return moveItemTo(item, LOGGED_IN_LIBRARY).then(() => objects);
    });
}

// Place a hold on an item for a new patron
function createHold(item, pickup_library_id) {
    return cy
        .task("insertSampleHold", { item, library_id: pickup_library_id })
        .then(objects => {
            cleanupLater(objects);
            cleanupLater({ category: objects.patron_category });
            cleanupQueryLater("DELETE FROM old_reserves WHERE reserve_id=?", [
                objects.hold.hold_id,
            ]);
            return objects;
        });
}

// Rows the check-in leaves behind for the item, which do not belong to any
// of the objects created by the tasks
function cleanupItemHistory(item) {
    cleanupQueryLater("DELETE FROM old_issues WHERE itemnumber=?", [
        item.item_id,
    ]);
    cleanupQueryLater("DELETE FROM statistics WHERE itemnumber=?", [
        item.item_id,
    ]);
}

function visitCheckin(params = "") {
    cy.visit(`/cgi-bin/koha/circ/checkin.pl${params}`);
    // The Vue app is mounted
    cy.get("#checkin-app #barcode-input").should("be.visible");
}

function checkin(barcode) {
    cy.get("#barcode-input").should("not.be.disabled").clear().type(barcode);
    cy.get("#checkin-app form.checkin-form button[type='submit']").click();
    return cy.wait("@checkin");
}

function checkoutCount(item) {
    return dbQuery("SELECT COUNT(*) AS count FROM issues WHERE itemnumber=?", [
        item.item_id,
    ]).then(rows => rows[0].count);
}

function checkinModal() {
    return cy.get("#checkin-app .modal.non-blocking .modal-content");
}

describe("Circulation - Check in", () => {
    before(() => {
        const names = Object.keys(PREFS);
        dbQuery(
            `SELECT variable, value FROM systempreferences WHERE variable IN (${names.map(() => "?").join(",")})`,
            names
        ).then(rows => {
            for (const row of rows) {
                originalPrefs[row.variable] = row.value;
            }
        });
    });

    beforeEach(() => {
        cleanupObjects = [];
        cleanupQueries = [];
        cy.login();
        cy.title().should("eq", "Koha staff interface");
        for (const [name, value] of Object.entries(PREFS)) {
            cy.set_syspref(name, value);
        }
        cy.intercept("POST", "/api/v1/checkins*").as("checkin");
    });

    afterEach(() => {
        cy.then(() => {
            for (const { sql, values } of cleanupQueries) {
                dbQuery(sql, values);
            }
        });
        cy.then(() => cy.task("deleteSampleObjects", cleanupObjects));
        cy.visit("/cgi-bin/koha/mainpage.pl");
        for (const [name, value] of Object.entries(originalPrefs)) {
            cy.set_syspref(name, value);
        }
    });

    describe("Simple check-in", () => {
        it("checks in a checked out item", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];

                visitCheckin();
                cy.get("#checkin-app").should(
                    "contain",
                    "No items have been checked in yet."
                );

                checkin(item.external_id)
                    .its("response.statusCode")
                    .should("eq", 200);

                cy.get("#checkins-table tbody tr")
                    .should("have.length", 1)
                    .first()
                    .should("contain", item.external_id)
                    .and("contain", objects.biblio.title)
                    .and("not.have.class", "table-warning");
                checkinModal().should("not.exist");
                cy.get("#checkin-app .alert-danger").should("not.exist");

                checkoutCount(item).should("eq", 0);
                dbQuery(
                    "SELECT COUNT(*) AS count FROM old_issues WHERE issue_id=?",
                    [objects.checkout.checkout_id]
                )
                    .its("0.count")
                    .should("eq", 1);

                // The input is ready for the next barcode
                cy.get("#barcode-input")
                    .should("have.value", "")
                    .and("have.focus");
            });
        });

        it("shows an error for an unknown barcode", () => {
            const barcode = `UNKNOWN-${Date.now()}`;

            visitCheckin();
            checkin(barcode).its("response.statusCode").should("eq", 404);

            cy.get("#checkin-app .alert-danger")
                .should("be.visible")
                .and("contain", `No item with barcode: ${barcode}`);
            cy.get("#checkins-table").should("not.exist");
            checkinModal().should("not.exist");
        });

        it("prefills the barcode from the URL without checking the item in", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];

                visitCheckin(
                    `?barcode=${encodeURIComponent(item.external_id)}`
                );

                cy.get("#barcode-input").should("have.value", item.external_id);
                // Give the page time to (wrongly) submit the barcode
                cy.wait(1000);
                cy.get("@checkin.all").should("have.length", 0);
                cy.get("#checkins-table").should("not.exist");
                checkoutCount(item).should("eq", 1);

                // Staff confirm the check-in explicitly
                cy.get(
                    "#checkin-app form.checkin-form button[type='submit']"
                ).click();
                cy.wait("@checkin")
                    .its("response.statusCode")
                    .should("eq", 200);
                cy.get("#checkins-table tbody tr")
                    .first()
                    .should("contain", item.external_id);
                checkoutCount(item).should("eq", 0);
            });
        });

        it("shows the item type check-in message as text", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];
                dbQuery(
                    "UPDATE itemtypes SET checkinmsg=?, checkinmsgtype='message' WHERE itemtype=?",
                    [
                        "Handle <b>with</b> care <img src=x onerror=alert(1)>",
                        objects.item_type.item_type_id,
                    ]
                );

                visitCheckin();
                checkin(item.external_id);

                cy.get("#checkins-table tbody tr")
                    .first()
                    .should("contain", item.external_id);
                cy.contains(
                    "#checkin-app .alert",
                    "Handle <b>with</b> care <img src=x onerror=alert(1)>"
                )
                    .should("be.visible")
                    .within(() => {
                        cy.get("b").should("not.exist");
                        cy.get("img").should("not.exist");
                    });
                checkoutCount(item).should("eq", 0);
            });
        });
    });

    describe("Blocked check-in", () => {
        it("does not check in a withdrawn item with BlockReturnOfWithdrawnItems", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];
                dbQuery(
                    "UPDATE items SET withdrawn=1, withdrawn_on=NOW() WHERE itemnumber=?",
                    [item.item_id]
                );

                visitCheckin();
                checkin(item.external_id)
                    .its("response.statusCode")
                    .should("eq", 403);

                checkinModal()
                    .should("be.visible")
                    .and("contain", "Cannot check in")
                    .and(
                        "contain",
                        "This item is withdrawn and cannot be checked in."
                    );
                cy.get("#checkins-table tbody tr")
                    .first()
                    .should("have.class", "table-danger")
                    .and("contain", "Blocked");

                checkinModal().contains("button", "OK").click();
                checkinModal().should("not.exist");
                cy.get("#checkins-table tbody tr")
                    .first()
                    .should("contain", "Not checked in");

                checkoutCount(item).should("eq", 1);
            });
        });
    });

    describe("Module policy", () => {
        it("refreshes the policy when the server refuses a return date", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];

                visitCheckin();
                cy.get("#show-circ-settings a").click();
                cy.get("#return_date_override_fields").should("be.visible");

                // The return date override is disabled after the page was
                // loaded: the page still offers it
                cy.set_syspref("SpecifyReturnDate", "0");

                const yesterday = new Date();
                yesterday.setDate(yesterday.getDate() - 1);
                cy.get("#return-date-override").selectFlatpickrDate(yesterday);
                cy.get("#show-circ-settings a").click();
                cy.get("#checkin-app .checkin-active-settings").should(
                    "contain",
                    "Return date:"
                );

                checkin(item.external_id).then(({ response }) => {
                    expect(response.statusCode).to.eq(403);
                    expect(response.body.error_code).to.eq(
                        "return_date_not_allowed"
                    );
                    expect(response.body.policy.module).to.eq("checkin");
                    expect(
                        response.body.policy.checkin.specify_return_date
                    ).to.eq(false);
                });

                cy.get("#checkin-app .alert-danger")
                    .should("be.visible")
                    .and(
                        "contain",
                        "Specifying a return date is not allowed. The item was not checked in."
                    );
                // The page no longer offers the return date
                cy.get("#checkin-app .checkin-active-settings").should(
                    "not.exist"
                );
                cy.get("#show-circ-settings a").click();
                cy.get("#return_date_override_fields").should("not.exist");
                checkinModal().should("not.exist");

                checkoutCount(item).should("eq", 1);
            });
        });
    });

    describe("Holds", () => {
        it("sets the hold waiting when it is confirmed", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];
                createHold(item, LOGGED_IN_LIBRARY).then(({ hold }) => {
                    cy.intercept(
                        "POST",
                        "/api/v1/checkins/*/hold_confirmation*"
                    ).as("holdConfirmation");

                    visitCheckin();
                    checkin(item.external_id);

                    checkinModal()
                        .should("be.visible")
                        .and("contain", "Hold found")
                        .and("contain", objects.biblio.title);
                    cy.get("#checkins-table tbody tr")
                        .first()
                        .should("have.class", "table-warning");
                    checkoutCount(item).should("eq", 0);

                    checkinModal()
                        .contains("button", "Confirm hold (Y)")
                        .click();
                    cy.wait("@holdConfirmation")
                        .its("response.statusCode")
                        .should("eq", 201);

                    checkinModal().should("not.exist");
                    cy.get("#checkins-table tbody tr")
                        .first()
                        .should("not.have.class", "table-warning");
                    dbQuery(
                        "SELECT found, itemnumber, branchcode FROM reserves WHERE reserve_id=?",
                        [hold.hold_id]
                    ).then(rows => {
                        expect(rows).to.have.length(1);
                        expect(rows[0].found).to.eq("W");
                        expect(rows[0].itemnumber).to.eq(item.item_id);
                        expect(rows[0].branchcode).to.eq(LOGGED_IN_LIBRARY);
                    });
                });
            });
        });

        it("transfers the item when the hold is for another library", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];
                const pickup_library = objects.libraries[0];
                createHold(item, pickup_library.library_id).then(({ hold }) => {
                    cy.intercept(
                        "POST",
                        "/api/v1/checkins/*/hold_confirmation*"
                    ).as("holdConfirmation");

                    visitCheckin();
                    checkin(item.external_id);

                    checkinModal()
                        .should("be.visible")
                        .and("contain", "Hold found");
                    checkinModal()
                        .contains("button", "Confirm hold and transfer (Y)")
                        .click();
                    cy.wait("@holdConfirmation")
                        .its("response.statusCode")
                        .should("eq", 201);
                    checkinModal().should("not.exist");

                    dbQuery("SELECT found FROM reserves WHERE reserve_id=?", [
                        hold.hold_id,
                    ])
                        .its("0.found")
                        .should("eq", "T");
                    dbQuery(
                        "SELECT frombranch, tobranch, datesent, reason FROM branchtransfers WHERE itemnumber=? AND datearrived IS NULL AND datecancelled IS NULL",
                        [item.item_id]
                    ).then(rows => {
                        expect(rows).to.have.length(1);
                        expect(rows[0].frombranch).to.eq(LOGGED_IN_LIBRARY);
                        expect(rows[0].tobranch).to.eq(
                            pickup_library.library_id
                        );
                        expect(rows[0].datesent).to.not.eq(null);
                        expect(rows[0].reason).to.eq("Reserve");
                    });
                });
            });
        });

        it("cancels a waiting hold from the hold modal", () => {
            createCheckout().then(objects => {
                const item = objects.items[0];
                createHold(item, LOGGED_IN_LIBRARY).then(({ hold }) => {
                    // The item was returned and set waiting before
                    dbQuery("DELETE FROM issues WHERE itemnumber=?", [
                        item.item_id,
                    ]);
                    dbQuery(
                        "UPDATE reserves SET found='W', priority=0, waitingdate=CURDATE(), itemnumber=?, branchcode=? WHERE reserve_id=?",
                        [item.item_id, LOGGED_IN_LIBRARY, hold.hold_id]
                    );
                    cy.intercept(
                        "POST",
                        "/api/v1/checkins/*/hold_cancellation*"
                    ).as("holdCancellation");

                    visitCheckin();
                    checkin(item.external_id);

                    checkinModal()
                        .should("be.visible")
                        .and("contain", "Hold found (item is already waiting)");
                    checkinModal()
                        .contains("button", "Cancel hold (X)")
                        .click();

                    // Secondary pop-up asking for a cancellation reason
                    cy.get("#checkin-app .modal-dialog.modal-sm")
                        .should("be.visible")
                        .and("contain", "Cancellation reason:")
                        .contains("button", "Cancel hold")
                        .click();
                    cy.wait("@holdCancellation")
                        .its("response.statusCode")
                        .should("eq", 201);

                    cy.get("#checkin-app .modal").should("not.exist");
                    dbQuery(
                        "SELECT COUNT(*) AS count FROM reserves WHERE reserve_id=?",
                        [hold.hold_id]
                    )
                        .its("0.count")
                        .should("eq", 0);
                    dbQuery(
                        "SELECT cancellationdate FROM old_reserves WHERE reserve_id=?",
                        [hold.hold_id]
                    ).then(rows => {
                        expect(rows).to.have.length(1);
                        expect(rows[0].cancellationdate).to.not.eq(null);
                    });
                });
            });
        });
    });

    describe("Transfers", () => {
        it("sends the item back to its home library when confirmed", () => {
            cy.set_syspref("TransfersBlockCirc", "1");
            createCheckout({ stay_home: true }).then(objects => {
                const item = objects.items[0];
                const home_library = objects.libraries[0];
                cy.intercept(
                    "POST",
                    "/api/v1/checkins/*/transfer_confirmation*"
                ).as("transferConfirmation");

                visitCheckin();
                checkin(item.external_id);

                checkinModal()
                    .should("be.visible")
                    .and(
                        "contain",
                        `Please return this item to: ${home_library.name}`
                    );
                checkoutCount(item).should("eq", 0);
                // TransfersBlockCirc: the transfer must be acted on first
                cy.get("#barcode-input").should("be.disabled");

                checkinModal().contains("button", "Yes, transfer (Y)").click();
                cy.wait("@transferConfirmation")
                    .its("response.statusCode")
                    .should("eq", 201);
                checkinModal().should("not.exist");
                cy.get("#barcode-input").should("not.be.disabled");

                dbQuery(
                    "SELECT frombranch, tobranch, datesent FROM branchtransfers WHERE itemnumber=? AND datearrived IS NULL AND datecancelled IS NULL",
                    [item.item_id]
                ).then(rows => {
                    expect(rows).to.have.length(1);
                    expect(rows[0].frombranch).to.eq(LOGGED_IN_LIBRARY);
                    expect(rows[0].tobranch).to.eq(home_library.library_id);
                    expect(rows[0].datesent).to.not.eq(null);
                });
            });
        });
    });

    describe("Recalls", () => {
        it("sets the recall waiting when it is confirmed", () => {
            cy.set_syspref("UseRecalls", "staff");
            createCheckout().then(objects => {
                const item = objects.items[0];
                // Recalls need to be allowed for the item type
                dbQuery(
                    "INSERT INTO circulation_rules (branchcode, categorycode, itemtype, rule_name, rule_value) VALUES (NULL, NULL, ?, 'recalls_allowed', '1')",
                    [objects.item_type.item_type_id]
                );
                cleanupQueryLater(
                    "DELETE FROM circulation_rules WHERE itemtype=?",
                    [objects.item_type.item_type_id]
                );
                cy.task("insertSamplePatron", {
                    library: { library_id: LOGGED_IN_LIBRARY },
                }).then(({ patron, patron_category }) => {
                    cleanupLater({ patron, category: patron_category });
                    dbQuery(
                        "INSERT INTO recalls (patron_id, created_date, biblio_id, pickup_library_id, priority, status, item_id, item_level) VALUES (?, NOW(), ?, ?, 1, 'requested', ?, 1)",
                        [
                            patron.patron_id,
                            objects.biblio.biblio_id,
                            LOGGED_IN_LIBRARY,
                            item.item_id,
                        ]
                    ).then(result => {
                        const recall_id = result.insertId;
                        cleanupQueryLater(
                            "DELETE FROM recalls WHERE recall_id=?",
                            [recall_id]
                        );
                        cy.intercept(
                            "POST",
                            "/api/v1/checkins/*/recall_confirmation*"
                        ).as("recallConfirmation");

                        visitCheckin();
                        checkin(item.external_id);

                        checkinModal()
                            .should("be.visible")
                            .and("contain", "Recall found")
                            .and("contain", patron.surname);
                        checkoutCount(item).should("eq", 0);

                        checkinModal()
                            .contains("button", "Confirm recall (Y)")
                            .click();
                        cy.wait("@recallConfirmation")
                            .its("response.statusCode")
                            .should("eq", 201);
                        checkinModal().should("not.exist");

                        dbQuery(
                            "SELECT status, item_id FROM recalls WHERE recall_id=?",
                            [recall_id]
                        ).then(rows => {
                            expect(rows[0].status).to.eq("waiting");
                            expect(rows[0].item_id).to.eq(item.item_id);
                        });
                    });
                });
            });
        });
    });
});
