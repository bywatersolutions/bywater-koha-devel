/* global __ $date */

function showMessage(message, type) {
    var alert = $(
        '<div class="alert alert-' + type + '">' + message + "</div>"
    );
    $("#messages").append(alert);

    setTimeout(function () {
        alert.fadeOut(400, function () {
            $(this).remove();
        });
    }, 5000);
}

$(document).ready(function () {
    var librariesWhereCanEdit = window.libraries_where_can_edit || [];
    var canEditAnyLibrary = librariesWhereCanEdit.length === 0;

    function canEditItem(homebranch) {
        if (canEditAnyLibrary) {
            return true;
        }
        return librariesWhereCanEdit.includes(homebranch);
    }

    var oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
    var today = new Date();

    var fromDate = oneYearAgo.toISOString().split("T")[0];
    var toDate = today.toISOString().split("T")[0];

    setTimeout(function () {
        if ($("#from")[0]._flatpickr) {
            $("#from")[0]._flatpickr.setDate(fromDate);
        }
        if ($("#to")[0]._flatpickr) {
            $("#to")[0]._flatpickr.setDate(toDate);
        }
    }, 100);

    function buildApiUrl(baseUrl, dateField) {
        var from = $("#from").val();
        var to = $("#to").val();

        if (!from && !to) {
            return baseUrl;
        }

        var query = {};
        if (from && to) {
            query[dateField] = {
                "-between": [from + "T00:00:00Z", to + "T23:59:59Z"],
            };
        } else if (from) {
            query[dateField] = {
                ">=": from + "T00:00:00Z",
            };
        } else if (to) {
            query[dateField] = {
                "<=": to + "T23:59:59Z",
            };
        }

        return baseUrl + "?q=" + encodeURIComponent(JSON.stringify(query));
    }

    // Deleted biblios DataTable
    var biblios_table = $("#deleted_biblios_table").kohaTable({
        ajax: {
            url: buildApiUrl("/api/v1/deleted/biblios", "me.timestamp"),
        },
        embed: "items",
        order: [[3, "desc"]],
        columns: [
            {
                data: "biblio_id",
                searchable: true,
                orderable: true,
            },
            {
                data: "title",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display") {
                        return $("<div/>").text(data).html();
                    }
                    return data;
                },
            },
            {
                data: "author",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display") {
                        return data ? $("<div/>").text(data).html() : "";
                    }
                    return data || "";
                },
            },
            {
                data: "deleted_on",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display" && data) {
                        return $date(data);
                    }
                    return data;
                },
            },
            {
                data: function (row, type) {
                    if (type === "display") {
                        return (
                            '<button class="btn btn-sm btn-default restore-biblio" data-biblio-id="' +
                            row.biblio_id +
                            '" data-title="' +
                            $("<div/>").text(row.title).html() +
                            '"><i class="fa fa-undo" aria-hidden="true"></i> ' +
                            __("Restore") +
                            "</button>"
                        );
                    }
                    return "";
                },
                searchable: false,
                orderable: false,
            },
        ],
    });
    var biblios_table_api = biblios_table.DataTable();

    // Deleted items DataTable
    var items_table = $("#deleted_items_table").kohaTable({
        ajax: {
            url: buildApiUrl("/api/v1/deleted/items", "me.deleted_on"),
        },
        embed: "biblio",
        order: [[5, "desc"]],
        columns: [
            {
                data: "item_id",
                searchable: true,
                orderable: true,
            },
            {
                data: "biblio_id",
                searchable: true,
                orderable: true,
            },
            {
                data: "external_id",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display") {
                        return data ? $("<div/>").text(data).html() : "";
                    }
                    return data || "";
                },
            },
            {
                data: "callnumber",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display") {
                        return data ? $("<div/>").text(data).html() : "";
                    }
                    return data || "";
                },
            },
            {
                data: "home_library_id",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display") {
                        return data ? $("<div/>").text(data).html() : "";
                    }
                    return data || "";
                },
            },
            {
                data: "deleted_on",
                searchable: true,
                orderable: true,
                render: function (data, type, row) {
                    if (type === "display" && data) {
                        return $date(data);
                    }
                    return data || "";
                },
            },
            {
                data: function (row, type) {
                    if (type === "display") {
                        var canEdit = canEditItem(row.home_library_id);
                        var disabled = canEdit ? "" : " disabled";
                        var button =
                            '<button class="btn btn-sm btn-default restore-item" data-item-id="' +
                            row.item_id +
                            '" data-barcode="' +
                            $("<div/>")
                                .text(row.external_id || row.item_id)
                                .html() +
                            '"' +
                            disabled +
                            '><i class="fa fa-undo" aria-hidden="true"></i> ' +
                            __("Restore") +
                            "</button>";

                        if (!canEdit) {
                            return (
                                '<span title="' +
                                __(
                                    "You do not have permission to restore items from this library"
                                ) +
                                '" style="cursor: not-allowed;">' +
                                button +
                                "</span>"
                            );
                        }
                        return button;
                    }
                    return "";
                },
                searchable: false,
                orderable: false,
            },
        ],
    });
    var items_table_api = items_table.DataTable();

    // Initialize the modal items table as kohaTable
    var modal_items_table = null;
    var modal_items_table_api = null;

    // Populate and show the restore biblio modal.
    // preselectedItemId: optional item_id to pre-check in the items list.
    function showRestoreBiblioModal(
        biblio_id,
        title,
        author,
        items,
        preselectedItemId
    ) {
        $("#restore-modal-biblio-id").text(biblio_id);
        $("#restore-modal-biblio-title").text(title || __("(No title)"));
        $("#restore-modal-biblio-author").text(author || __("(No author)"));

        if (items.length > 0) {
            $("#items-section").show();

            if (modal_items_table_api) {
                modal_items_table_api.destroy();
            }

            modal_items_table = $("#deleted-items-list").kohaTable({
                data: items,
                paging: false,
                info: false,
                columns: [
                    {
                        data: function (row, type) {
                            if (type === "display") {
                                var canEdit = canEditItem(row.home_library_id);
                                var disabled = canEdit ? "" : " disabled";
                                var preselected =
                                    preselectedItemId &&
                                    row.item_id == preselectedItemId &&
                                    canEdit
                                        ? " checked"
                                        : "";
                                var checkbox =
                                    '<input type="checkbox" class="item-checkbox" data-item-id="' +
                                    row.item_id +
                                    '"' +
                                    disabled +
                                    preselected +
                                    ">";

                                if (!canEdit) {
                                    return (
                                        '<span title="' +
                                        __(
                                            "You do not have permission to restore items from this library"
                                        ) +
                                        '">' +
                                        checkbox +
                                        "</span>"
                                    );
                                }
                                return checkbox;
                            }
                            return "";
                        },
                        searchable: false,
                        orderable: false,
                    },
                    {
                        data: "item_id",
                        searchable: true,
                        orderable: true,
                    },
                    {
                        data: "external_id",
                        searchable: true,
                        orderable: true,
                        render: function (data, type, row) {
                            if (type === "display") {
                                return data
                                    ? $("<div/>").text(data).html()
                                    : __("(No barcode)");
                            }
                            return data || "";
                        },
                    },
                    {
                        data: "callnumber",
                        searchable: true,
                        orderable: true,
                        render: function (data, type, row) {
                            if (type === "display") {
                                return data
                                    ? $("<div/>").text(data).html()
                                    : "";
                            }
                            return data || "";
                        },
                    },
                    {
                        data: "home_library_id",
                        searchable: true,
                        orderable: true,
                        render: function (data, type, row) {
                            if (type === "display") {
                                var text = data
                                    ? $("<div/>").text(data).html()
                                    : "";
                                var canEdit = canEditItem(data);
                                if (!canEdit) {
                                    text +=
                                        ' <span class="badge bg-warning text-dark">' +
                                        __("No permission") +
                                        "</span>";
                                }
                                return text;
                            }
                            return data || "";
                        },
                    },
                ],
            });
            modal_items_table_api = modal_items_table.DataTable();
        } else {
            $("#items-section").hide();
        }

        $("#restore-biblio-with-items-button").data("biblio-id", biblio_id);

        var modal = new bootstrap.Modal(
            document.getElementById("restoreBiblioModal")
        );
        modal.show();
    }

    // Restore biblio handler (from deleted biblios table)
    $("#deleted_biblios_table").on("click", ".restore-biblio", function (e) {
        e.preventDefault();
        var button = $(this);
        var biblio_id = button.data("biblio-id");
        var row = biblios_table_api.row(button.closest("tr")).data();

        $("#restore-biblio-with-items-button").data("restore-button", button);
        showRestoreBiblioModal(
            biblio_id,
            row.title,
            row.author,
            row.items || []
        );
    });

    // Restore item handler
    $("#deleted_items_table").on("click", ".restore-item", function (e) {
        e.preventDefault();
        var button = $(this);
        var item_id = button.data("item-id");
        var barcode = button.data("barcode");
        var row = items_table_api.row(button.closest("tr")).data();

        // Check if biblio is deleted
        if (row.biblio && row.biblio.deleted_on) {
            // Show modal with biblio info
            $("#modal-biblio-id").text(row.biblio.biblio_id);
            $("#modal-biblio-title").text(row.biblio.title || __("(No title)"));
            $("#modal-biblio-author").text(
                row.biblio.author || __("(No author)")
            );

            // Store the item and biblio data for later
            $("#restore-biblio-button").data("biblio-id", row.biblio.biblio_id);
            $("#restore-biblio-button").data("item-id", item_id);
            $("#restore-biblio-button").data("item-button", button);

            var modal = new bootstrap.Modal(
                document.getElementById("deletedBiblioModal")
            );
            modal.show();
            return;
        }

        if (
            !confirm(
                __("Are you sure you want to restore item %s (%s)?").format(
                    item_id,
                    barcode
                )
            )
        ) {
            return;
        }

        button.prop("disabled", true);

        $.ajax({
            url: "/api/v1/deleted/items/" + item_id,
            type: "PUT",
            headers: {
                "x-koha-request-id": Math.random(),
            },
            success: function (data) {
                showMessage(
                    __("Item %s restored successfully").format(item_id),
                    "success"
                );
                items_table_api.ajax.reload();
            },
            error: function (xhr) {
                var error_msg = __("Error restoring item %s").format(item_id);
                if (xhr.responseJSON && xhr.responseJSON.error) {
                    error_msg += ": " + xhr.responseJSON.error;
                }
                showMessage(error_msg, "danger");
                button.prop("disabled", false);
            },
        });
    });

    // "Restore bibliographic record" button in the deleted-bib warning modal:
    // fetch the biblio (with items) and open the full restore modal with the
    // originally clicked item pre-selected.
    $("#restore-biblio-button").on("click", function () {
        var button = $(this);
        var biblio_id = button.data("biblio-id");
        var original_item_id = button.data("item-id");
        var item_button = button.data("item-button");

        button.prop("disabled", true);

        $.ajax({
            url: "/api/v1/deleted/biblios/" + biblio_id,
            type: "GET",
            headers: {
                Accept: "application/json",
                "x-koha-embed": "items",
            },
            success: function (biblio) {
                bootstrap.Modal.getInstance(
                    document.getElementById("deletedBiblioModal")
                ).hide();
                $("#restore-biblio-with-items-button").data(
                    "restore-button",
                    item_button
                );
                showRestoreBiblioModal(
                    biblio.biblio_id,
                    biblio.title,
                    biblio.author,
                    biblio.items || [],
                    original_item_id
                );
                button.prop("disabled", false);
            },
            error: function (xhr) {
                var error_msg = __(
                    "Error loading bibliographic record %s"
                ).format(biblio_id);
                if (xhr.responseJSON && xhr.responseJSON.error) {
                    error_msg += ": " + xhr.responseJSON.error;
                }
                showMessage(error_msg, "danger");
                button.prop("disabled", false);
            },
        });
    });

    // Select all items checkbox
    $("#select-all-items").on("change", function () {
        var checked = $(this).prop("checked");
        $(".item-checkbox:not(:disabled)").prop("checked", checked);
    });

    // Restore biblio with items
    $("#restore-biblio-with-items-button").on("click", function () {
        var button = $(this);
        var biblio_id = button.data("biblio-id");
        var restore_button = button.data("restore-button");

        button.prop("disabled", true);

        $.ajax({
            url: "/api/v1/deleted/biblios/" + biblio_id,
            type: "PUT",
            headers: {
                "x-koha-request-id": Math.random(),
            },
            success: function (data) {
                showMessage(
                    __("Bibliographic record %s restored successfully").format(
                        biblio_id
                    ),
                    "success"
                );

                var selected_items = [];
                $(".item-checkbox:checked").each(function () {
                    selected_items.push($(this).data("item-id"));
                });

                if (selected_items.length > 0) {
                    var items_restored = 0;
                    var items_failed = 0;

                    selected_items.forEach(function (item_id) {
                        $.ajax({
                            url: "/api/v1/deleted/items/" + item_id,
                            type: "PUT",
                            headers: {
                                "x-koha-request-id": Math.random(),
                            },
                            success: function (data) {
                                items_restored++;
                                if (
                                    items_restored + items_failed ===
                                    selected_items.length
                                ) {
                                    if (items_restored > 0) {
                                        showMessage(
                                            __(
                                                "%s item(s) restored successfully"
                                            ).format(items_restored),
                                            "success"
                                        );
                                    }
                                    if (items_failed > 0) {
                                        showMessage(
                                            __(
                                                "%s item(s) failed to restore"
                                            ).format(items_failed),
                                            "danger"
                                        );
                                    }
                                    items_table_api.ajax.reload();
                                }
                            },
                            error: function (xhr) {
                                items_failed++;
                                if (
                                    items_restored + items_failed ===
                                    selected_items.length
                                ) {
                                    if (items_restored > 0) {
                                        showMessage(
                                            __(
                                                "%s item(s) restored successfully"
                                            ).format(items_restored),
                                            "success"
                                        );
                                    }
                                    if (items_failed > 0) {
                                        showMessage(
                                            __(
                                                "%s item(s) failed to restore"
                                            ).format(items_failed),
                                            "danger"
                                        );
                                    }
                                    items_table_api.ajax.reload();
                                }
                            },
                        });
                    });
                }

                bootstrap.Modal.getInstance(
                    document.getElementById("restoreBiblioModal")
                ).hide();
                biblios_table_api.ajax.reload();
                items_table_api.ajax.reload();
                button.prop("disabled", false);
            },
            error: function (xhr) {
                var error_msg = __(
                    "Error restoring bibliographic record %s"
                ).format(biblio_id);
                if (xhr.responseJSON && xhr.responseJSON.error) {
                    error_msg += ": " + xhr.responseJSON.error;
                }
                showMessage(error_msg, "danger");
                button.prop("disabled", false);
            },
        });
    });

    $("#filter_table").on("click", function () {
        biblios_table_api.ajax
            .url(buildApiUrl("/api/v1/deleted/biblios", "me.timestamp"))
            .load();
        items_table_api.ajax
            .url(buildApiUrl("/api/v1/deleted/items", "me.deleted_on"))
            .load();
    });

    $("#clear_filters").on("click", function () {
        $("#from").val("");
        $("#to").val("");
        biblios_table_api.ajax.url("/api/v1/deleted/biblios").load();
        items_table_api.ajax.url("/api/v1/deleted/items").load();
    });
});
