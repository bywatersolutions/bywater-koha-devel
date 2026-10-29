import { defineStore } from "pinia";
import { computed, reactive, ref } from "vue";
import { APIClient } from "../fetch/api-client.js";
import { $__ } from "@koha-vue/i18n";

export const useCheckinStore = defineStore("checkin", () => {
    // Flat view of the module policy: the check-in keys plus `global`
    const policy = reactive({});
    applyPolicy(window.__MODULE_POLICY__);
    const libraryId = window.__LIBRARY_ID__ || null;
    const tableSettings = window.__TABLE_SETTINGS__ || {};
    const libraries = ref({});
    const checkins = ref([]);
    const processing = ref(false);

    // Fetch libraries for name resolution
    APIClient.library.libraries
        .getAll()
        .then(libs => {
            const map = {};
            for (const lib of libs || []) {
                map[lib.library_id] = lib.name;
            }
            libraries.value = map;
        })
        .catch(() => {});

    // Fetch authorised value descriptions used to display item status
    // changes (UpdateNotForLoanStatusOnCheckin, UpdateItemLocationOnCheckin)
    const authorisedValues = ref({ NOT_LOAN: {}, LOC: {} });
    for (const category of Object.keys(authorisedValues.value)) {
        APIClient.authorised_values.values
            .get(category)
            .then(values => {
                const map = {};
                for (const av of values || []) {
                    map[av.value] = av.description;
                }
                authorisedValues.value = {
                    ...authorisedValues.value,
                    [category]: map,
                };
            })
            .catch(() => {});
    }
    const lastError = ref(null);
    const _inflight = new Set();

    const maxItems = policy.max_returned_items || 20;

    /**
     * Items in the queue that need staff attention (modal or inline action).
     * Computed from checkins with pending statuses.
     */
    const pendingItems = computed(() =>
        checkins.value.filter(
            c =>
                c._status === "pending_confirmation" ||
                c._status === "needs_action" ||
                c._status === "blocked"
        )
    );

    /**
     * The first pending item that should be shown in a modal.
     * Only one modal at a time — the rest stay as yellow rows.
     */
    const nextModalItem = computed(() => pendingItems.value[0] || null);

    /**
     * Perform a checkin. Adds entry to table regardless of outcome.
     * On 412: stores JWT and confirmation details for later resolution.
     * On 200 with hold/transfer/recall: marks as needs_action.
     */
    async function checkin(barcode, options = {}) {
        // Prevent double-scan: reject if this barcode has a request in-flight
        if (_inflight.has(barcode)) {
            return { status: "duplicate", data: null };
        }
        _inflight.add(barcode);

        processing.value = true;
        lastError.value = null;

        const body = { external_id: barcode };
        if (libraryId) body.library_id = libraryId;
        if (options.exempt_fine) body.exempt_fine = true;
        if (options.dropbox_mode) body.dropbox_mode = true;
        if (options.return_date) body.return_date = options.return_date;

        try {
            const client = APIClient.checkin;
            const response = await client.checkins.create(body, {
                confirmation: options.confirmation || null,
            });

            const data = await response.json();

            if (response.status === 412) {
                // Confirmation required — add to table as pending
                _addEntry({
                    checkin_id: null,
                    item: data.item || null,
                    checkout: data.checkout || null,
                    messages: [],
                    _status: "pending_confirmation",
                    _confirmation_token: data.confirmation_token,
                    _confirms: data.confirms || {},
                    _warnings: data.warnings || {},
                    _action_type: null,
                    _barcode: barcode,
                    _options: options,
                });
                return { status: "pending_confirmation", data };
            }

            if (response.status === 403 && data.policy) {
                // Refused because of the policy (e.g. a capability was
                // revoked since the page was loaded): refresh it so the UI
                // stops offering the option, and tell why
                applyPolicy(data.policy);
                lastError.value = _policyErrorMessage(data);
                return { status: "error", data };
            }

            if (response.status === 403) {
                // Blocked — add as blocked row
                _addEntry({
                    checkin_id: null,
                    item: data.item || null,
                    checkout: null,
                    blockers: data.blockers || {},
                    messages: [
                        {
                            message: data.error_code || "checkin_blocked",
                            type: "error",
                        },
                    ],
                    _status: "blocked",
                    _confirmation_token: null,
                    _confirms: {},
                    _warnings: {},
                    _action_type: null,
                    _barcode: barcode,
                    _options: options,
                });
                return { status: "blocked", data };
            }

            if (response.status === 404) {
                lastError.value = $__("No item with barcode: %s").replace(
                    "%s",
                    barcode
                );
                return { status: "not_found", data };
            }

            if (!response.ok) {
                lastError.value = data.error || $__("An error occurred");
                return { status: "error", data };
            }

            // Success — determine if post-checkin action needed
            const actionType = _detectActionType(data);
            const status = actionType ? "needs_action" : "success";

            _addEntry({
                ...data,
                _status: status,
                _confirmation_token: null,
                _confirms: {},
                _warnings: {},
                _action_type: actionType,
                _barcode: barcode,
                _options: options,
            });

            return { status, data };
        } catch (error) {
            lastError.value = $__("Network error. Please try again.");
            return { status: "error", data: null };
        } finally {
            _inflight.delete(barcode);
            processing.value = false;
        }
    }

    /**
     * Confirm a pre-checkin confirmation (412 flow).
     * Re-issues the checkin request with the stored JWT.
     */
    async function confirmPending(entry) {
        const idx = checkins.value.indexOf(entry);
        if (idx === -1)
            return { status: "error", message: $__("Entry not found") };

        processing.value = true;

        try {
            const client = APIClient.checkin;
            const body = { external_id: entry._barcode };
            if (libraryId) body.library_id = libraryId;
            if (entry._options.exempt_fine) body.exempt_fine = true;
            if (entry._options.dropbox_mode) body.dropbox_mode = true;
            if (entry._options.return_date)
                body.return_date = entry._options.return_date;
            if (entry._options.verified_bundle_barcodes)
                body.verified_bundle_barcodes =
                    entry._options.verified_bundle_barcodes;

            const response = await client.checkins.create(body, {
                confirmation: entry._confirmation_token,
            });

            const data = await response.json();

            if (!response.ok) {
                // Confirmation failed — keep as pending
                if (data.policy) {
                    applyPolicy(data.policy);
                    lastError.value = _policyErrorMessage(data);
                    return { status: "error", data };
                }
                lastError.value = data.error || $__("Confirmation failed");
                return { status: "error", data };
            }

            // Confirmed successfully — update entry in place
            const actionType = _detectActionType(data);
            const status = actionType ? "needs_action" : "success";

            checkins.value[idx] = {
                ...data,
                _status: status,
                _confirmation_token: null,
                _confirms: {},
                _warnings: {},
                _action_type: actionType,
                _barcode: entry._barcode,
                _options: entry._options,
            };

            return { status, data };
        } catch (error) {
            lastError.value = $__("Network error during confirmation.");
            return { status: "error", data: null };
        } finally {
            processing.value = false;
        }
    }

    /**
     * Dismiss a pending confirmation without confirming (staff said "No").
     * Marks the row as dismissed.
     */
    function dismissPending(entry) {
        const idx = checkins.value.indexOf(entry);
        if (idx === -1) return;
        checkins.value[idx] = {
            ...entry,
            _status: "dismissed",
            _confirmation_token: null,
        };
    }

    /**
     * Ignore a post-checkin action (hold, recall, claim). The item was
     * checked in, so the row is marked as a successful checkin.
     */
    function ignoreAction(entry) {
        const idx = checkins.value.indexOf(entry);
        if (idx === -1) return;
        checkins.value[idx] = {
            ...entry,
            _status: "success",
            _action_type: null,
        };
    }

    /**
     * Resolve a post-checkin action (hold, transfer, recall).
     */
    async function resolveAction(entry, action, params = {}) {
        const idx = checkins.value.indexOf(entry);
        if (idx === -1)
            return { status: "error", message: $__("Entry not found") };

        try {
            const client = APIClient.checkin;
            const checkinId = entry.checkin_id;
            // Tokens for the follow-up actions, returned on checkin
            const tokens = entry.action_tokens || {};
            let data;

            switch (action) {
                case "confirm_hold":
                    data = await client.checkins.confirmHold(checkinId, {
                        action_token: tokens.hold_confirmation,
                    });
                    break;
                case "cancel_hold": {
                    const response = await client.checkins.cancelHold(
                        checkinId,
                        {
                            reason: params.reason,
                            forgive_hold_fees: params.forgive_hold_fees,
                            action_token: tokens.hold_cancellation,
                        }
                    );
                    data = await response.json();
                    if (!response.ok) {
                        if (data.policy) {
                            applyPolicy(data.policy);
                            throw new Error(_policyErrorMessage(data));
                        }
                        throw new Error(data.error || $__("An error occurred"));
                    }
                    break;
                }
                case "confirm_transfer": {
                    // Without AutomaticItemReturn no transfer was created:
                    // request it to the library the checkin pointed at
                    const needs = _needsTransferMessage(entry);
                    if (entry.transfer_id) {
                        data = await client.checkins.confirmTransfer(
                            checkinId,
                            { action_token: tokens.transfer_confirmation }
                        );
                    } else if (needs) {
                        data = await client.checkins.confirmTransfer(
                            checkinId,
                            {
                                to_library_id: needs.payload?.to_library,
                                reason: needs.payload?.trigger,
                                action_token: tokens.transfer_confirmation,
                            }
                        );
                    }
                    break;
                }
                case "cancel_transfer":
                    if (entry.transfer_id) {
                        data = await client.checkins.cancelTransfer(checkinId, {
                            action_token: tokens.transfer_cancellation,
                        });
                    }
                    break;
                case "confirm_recall":
                    data = await client.checkins.confirmRecall(checkinId, {
                        action_token: tokens.recall_confirmation,
                    });
                    break;
            }

            // Update entry in place — action resolved
            // Preserve item/checkout data from the original response
            // since sub-resource endpoints may not embed them fully
            const existing = checkins.value[idx];
            const resolved = {
                ...existing,
                _status: "success",
                _action_type: null,
            };
            // Confirming the hold started a transfer to the pickup library:
            // show it on the row
            if (action === "confirm_hold" && data?.transfer) {
                resolved.transfer_id = data.transfer.transfer_id;
                resolved.messages = [
                    ...(existing.messages || []),
                    {
                        message: "transferred",
                        type: "info",
                        payload: {
                            transfer_id: data.transfer.transfer_id,
                            to_library: data.transfer.to_library_id,
                            trigger: data.transfer.reason,
                        },
                    },
                ];
            }
            // The transfer was requested on confirmation: show it as sent
            if (
                action === "confirm_transfer" &&
                !existing.transfer_id &&
                data?.transfer
            ) {
                resolved.transfer_id = data.transfer.transfer_id;
                resolved.messages = (existing.messages || []).map(m =>
                    m.message === "needs_transfer"
                        ? {
                              ...m,
                              message: "transferred",
                              payload: {
                                  ...m.payload,
                                  transfer_id: data.transfer.transfer_id,
                              },
                          }
                        : m
                );
            }
            // The transfer was cancelled: stop showing it on the row
            if (action === "cancel_transfer") {
                resolved.transfer_id = null;
                resolved.messages = (existing.messages || []).filter(
                    m =>
                        ![
                            "needs_transfer",
                            "transferred",
                            "wrong_transfer",
                        ].includes(m.message)
                );
            }
            checkins.value[idx] = resolved;

            return { status: "ok", data };
        } catch (error) {
            // The action stays pending: tell the user why it did not go through
            lastError.value = error.message;
            return { status: "error", message: error.message };
        }
    }

    /**
     * Detect if a successful checkin requires post-action (hold/transfer/recall).
     */
    function _needsTransferMessage(data) {
        return (data.messages || []).find(m => m.message === "needs_transfer");
    }

    function _detectActionType(data) {
        const messages = data.messages || [];
        if (
            data.hold_id &&
            messages.some(m => m.message === "hold_found") &&
            !messages.some(m => m.message === "hold_auto_filled")
        ) {
            return "hold";
        }
        if (messages.some(m => m.message === "wrong_transfer")) {
            return "transfer";
        }
        if (
            data.transfer_id &&
            messages.some(
                m =>
                    m.message === "needs_transfer" ||
                    m.message === "transferred"
            )
        ) {
            return "transfer";
        }
        // The item needs a transfer that was not created (AutomaticItemReturn
        // disabled): ask whether to transfer it now
        if (_needsTransferMessage(data)) {
            return "transfer";
        }
        if (
            data.recall_id &&
            messages.some(m => m.message === "recall_found")
        ) {
            return "recall";
        }
        if (messages.some(m => m.message === "return_claim")) {
            return "claim";
        }
        return null;
    }

    /**
     * Apply a module policy envelope (as defined by the module_policy API
     * definition) to the reactive policy: the check-in keys are flattened
     * next to the global ones. Used for the policy bootstrapped on page
     * load and the one returned when the API refuses a request because of
     * it.
     */
    function applyPolicy(envelope) {
        if (!envelope || envelope.module !== "checkin") return;
        Object.assign(policy, envelope.checkin || {}, {
            global: envelope.global || {},
        });
    }

    /**
     * Message for a request refused because of the module policy.
     */
    function _policyErrorMessage(data) {
        const messages = {
            no_permission_for_exempt_fine: $__(
                "You are not allowed to forgive overdue charges. The item was not checked in."
            ),
            no_permission_for_forgive_hold_fees: $__(
                "You are not allowed to forgive hold fees. The hold was not cancelled."
            ),
            return_date_not_allowed: $__(
                "Specifying a return date is not allowed. The item was not checked in."
            ),
        };
        return (
            messages[data.error_code] || data.error || $__("An error occurred")
        );
    }

    /**
     * Add entry to the checkins list (most recent first), trim to max.
     */
    function _addEntry(entry) {
        checkins.value.unshift(entry);
        if (checkins.value.length > maxItems) {
            checkins.value = checkins.value.slice(0, maxItems);
        }
    }

    return {
        policy,
        libraries,
        authorisedValues,
        tableSettings,
        checkins,
        processing,
        lastError,
        pendingItems,
        nextModalItem,
        checkin,
        confirmPending,
        dismissPending,
        ignoreAction,
        resolveAction,
        applyPolicy,
    };
});
