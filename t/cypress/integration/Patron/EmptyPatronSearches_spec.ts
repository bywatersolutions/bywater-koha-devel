describe("EmptyPatronSearches", () => {
    beforeEach(() => {
        cy.login();
        cy.title().should("eq", "Koha staff interface");
        cy.task("query", {
            sql: "SELECT value FROM systempreferences WHERE variable='EmptyPatronSearches'",
        }).then(rows => {
            cy.wrap(rows[0] ? rows[0].value : 1).as(
                "syspref_EmptyPatronSearches"
            );
        });
    });

    afterEach(function () {
        cy.set_syspref("EmptyPatronSearches", this.syspref_EmptyPatronSearches);
    });

    const search_btn =
        "aside form.patron_search_form .search_patron_filter_btn";

    describe("Sidebar search", () => {
        it("disables the search button until a search term is entered", () => {
            cy.set_syspref("EmptyPatronSearches", 0).then(() => {
                cy.visit("/cgi-bin/koha/members/members-home.pl");

                cy.get(search_btn).should("be.disabled");

                cy.get("#search_patron_filter").type("abc");
                cy.get(search_btn).should("not.be.disabled");

                cy.get("#search_patron_filter").clear();
                cy.get(search_btn).should("be.disabled");
            });
        });

        it("enables the search button when a category is selected", () => {
            cy.set_syspref("EmptyPatronSearches", 0).then(() => {
                cy.visit("/cgi-bin/koha/members/members-home.pl");

                cy.get(search_btn).should("be.disabled");

                cy.get("aside form.patron_search_form .categorycode_filter")
                    .find("option")
                    .eq(1)
                    .then(option => {
                        cy.get(
                            "aside form.patron_search_form .categorycode_filter"
                        ).select(option.val());
                    });

                cy.get(search_btn).should("not.be.disabled");
            });
        });

        it("leaves the search button enabled when empty searches are allowed", () => {
            cy.set_syspref("EmptyPatronSearches", 1).then(() => {
                cy.visit("/cgi-bin/koha/members/members-home.pl");
                cy.get(search_btn).should("not.be.disabled");
            });
        });
    });

    describe("Header search", () => {
        it("prevents an empty search when empty searches are disallowed", () => {
            cy.set_syspref("EmptyPatronSearches", 0).then(() => {
                cy.visit("/cgi-bin/koha/members/members-home.pl");

                cy.get("#patron_header_search button[type='submit']").click();

                cy.get(".tooltip").should("be.visible");
                cy.url().should("include", "members-home.pl");
            });
        });

        it("allows an empty search when empty searches are allowed", () => {
            cy.set_syspref("EmptyPatronSearches", 1).then(() => {
                cy.visit("/cgi-bin/koha/members/members-home.pl");

                cy.get("#patron_header_search button[type='submit']").click();

                cy.url().should("include", "member.pl");
            });
        });
    });
});
