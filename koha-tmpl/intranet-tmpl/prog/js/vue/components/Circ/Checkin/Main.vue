<template>
    <div id="checkin-app">
        <h1>{{ $__("Check in") }}</h1>

        <div v-if="lastError" class="alert alert-danger" role="alert">
            {{ lastError }}
        </div>

        <BarcodeInput
            ref="barcodeInputRef"
            :disabled="isInputBlocked"
            :dropbox-mode="checkinOptions.dropbox_mode"
            :exempt-fine="checkinOptions.exempt_fine"
            @submit="onBarcodeScan"
            @toggle-options="showOptions = !showOptions"
        />

        <!-- Active settings indicators (visible when panel is collapsed) -->
        <div
            v-if="!showOptions && hasActiveSettings"
            class="checkin-active-settings mt-1"
        >
            <span
                v-if="checkinOptions.exempt_fine"
                class="badge text-bg-warning me-1"
            >
                <i class="fa fa-check"></i> {{ $__("Fines forgiven") }}
            </span>
            <span
                v-if="checkinOptions.dropbox_mode"
                class="badge text-bg-warning me-1"
            >
                <i class="fa fa-check"></i> {{ $__("Book drop mode") }}
                <span v-if="dropboxDate">
                    ({{
                        $__("Effective checkin date is %s").replace(
                            "%s",
                            dropboxDate
                        )
                    }})
                </span>
            </span>
            <span
                v-if="checkinOptions.return_date"
                class="badge text-bg-warning me-1"
            >
                <i class="fa fa-check"></i> {{ $__("Return date:") }}
                {{ formatDate(checkinOptions.return_date) }}
            </span>
        </div>

        <CheckinOptions
            v-show="showOptions"
            ref="checkinOptionsRef"
            class="mt-2"
            @update:options="onOptionsUpdate"
        />

        <!-- Detailed messages for the last checkin -->
        <div
            v-if="lastCheckinMessages.length"
            class="mt-3"
            @click="onMessagesClick"
        >
            <div
                v-for="msg in lastCheckinMessages"
                :key="msg.message"
                class="alert"
                :class="msg.alertClass"
            >
                <p class="mb-0" v-html="msg.text"></p>
            </div>
        </div>

        <!-- Pending items count indicator -->
        <div
            v-if="pendingItems.length > 1"
            class="alert alert-warning mt-3"
            role="alert"
        >
            <i class="fa fa-exclamation-triangle"></i>
            {{
                $__("%s items require attention").replace(
                    "%s",
                    pendingItems.length
                )
            }}
        </div>

        <CheckedInItems
            :checkins="checkins"
            class="mt-4"
            @show-modal="showModalFor"
            @resolve-claim="onResolveClaimFromRow"
        />

        <!-- Confirmation panel — shows one pending item at a time -->
        <ConfirmationModal
            :item="activeModalItem"
            :confirming="processing"
            @close="onClose"
            @confirm="onConfirm"
            @dismiss="onDismiss"
            @ignore="onIgnore"
            @resolve="onResolve"
            @resolve-claim="onResolveClaimFromModal"
            @open-cancel-hold="onOpenCancelHold"
        />

        <HoldCancellationModal
            :visible="showHoldCancellationModal"
            :cancelling="processing"
            @confirm="onConfirmHoldCancellation"
            @close="showHoldCancellationModal = false"
        />

        <ResolveClaimModal
            :claim-id="activeClaimId"
            :visible="showClaimModal"
            @resolved="onClaimResolved"
            @close="showClaimModal = false"
        />

        <BundleVerificationModal
            :visible="showBundleModal"
            :item-id="bundleItemId"
            :barcode="bundleBarcode"
            @confirm="onBundleConfirm"
            @cancel="showBundleModal = false"
        />
    </div>
</template>

<script>
import {
    computed,
    nextTick,
    onBeforeUnmount,
    onMounted,
    reactive,
    ref,
    watch,
} from "vue";
import { storeToRefs } from "pinia";
import { useCheckinStore } from "../../../stores/checkin.js";
import BarcodeInput from "./BarcodeInput.vue";
import CheckedInItems from "./CheckedInItems.vue";
import CheckinOptions from "./CheckinOptions.vue";
import ConfirmationModal from "./ConfirmationModal.vue";
import HoldCancellationModal from "./HoldCancellationModal.vue";
import ResolveClaimModal from "./ResolveClaimModal.vue";
import BundleVerificationModal from "./BundleVerificationModal.vue";
import { $__ } from "@koha-vue/i18n";
import { printHoldSlip } from "./slip-printer.js";

// Values interpolated into the v-html alert boxes must be escaped
function escapeHtml(value) {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function formatDate(value) {
    if (!value) return "";
    return typeof $date === "function" ? $date(value) : value;
}

export default {
    components: {
        BarcodeInput,
        CheckedInItems,
        CheckinOptions,
        ConfirmationModal,
        HoldCancellationModal,
        ResolveClaimModal,
        BundleVerificationModal,
    },
    setup() {
        const store = useCheckinStore();
        const {
            checkins,
            processing,
            lastError,
            pendingItems,
            nextModalItem,
            policy,
        } = storeToRefs(store);
        const barcodeInputRef = ref(null);
        const checkinOptionsRef = ref(null);
        const activeModalItem = ref(null);
        const showOptions = ref(false);
        const showClaimModal = ref(false);
        const activeClaimId = ref(null);
        const showBundleModal = ref(false);
        const bundleItemId = ref(null);
        const bundleBarcode = ref("");
        const showHoldCancellationModal = ref(false);
        const holdCancellationItem = ref(null);
        // Items removed from their bundle from the "in bundle" alert
        const removedFromBundle = ref(new Set());

        // Effective return date used in book drop mode
        const dropboxDate = computed(() =>
            formatDate(policy.value.dropbox_date)
        );

        const checkinOptions = reactive({
            dropbox_mode: false,
            exempt_fine: false,
            forgive_hold_fees: false,
            return_date: null,
        });

        function onOptionsUpdate(options) {
            Object.assign(checkinOptions, options);
        }

        // Async mode: staff can keep scanning while modals are showing.
        // Items needing attention queue as yellow rows and modals show
        // one at a time. The exception is a transfer modal when
        // TransfersBlockCirc is set: it must be acted on first.
        const isInputBlocked = computed(
            () =>
                activeModalItem.value?._action_type === "transfer" &&
                !!policy.value.transfers_block
        );

        watch(isInputBlocked, blocked => {
            if (!blocked) nextTick(() => refocusInput());
        });

        const hasActiveSettings = computed(
            () =>
                checkinOptions.exempt_fine ||
                checkinOptions.dropbox_mode ||
                checkinOptions.return_date
        );

        // Detailed messages for the most recent checkin (shown as alert boxes)
        const lastCheckinMessages = computed(() => {
            if (!checkins.value.length) return [];
            const latest = checkins.value[0];
            if (latest._status !== "success") return [];
            const messages = latest.messages || [];
            const detailed = [];
            const feeMessages = {
                lost_item_fee_refunded: {
                    text: $__(
                        "A refund for the lost item charge has been applied to the borrowing patron's account."
                    ),
                    alertClass: "alert-info",
                },
                lost_item_fee_charged: {
                    text: $__(
                        "A refund for the lost item charge has been applied to the borrowing patron's account, and new overdue charge has been calculated and applied."
                    ),
                    alertClass: "alert-info",
                },
                lost_item_fee_restored: {
                    text: $__(
                        "A refund for the lost item charge has been applied to the borrowing patron's account and if an overdue fine was forgiven when the item was marked as lost, it has been reverted."
                    ),
                    alertClass: "alert-info",
                },
                lost_item_payment_not_refunded: {
                    text: $__(
                        "The payment for the lost item is older than the refund threshold. No refund applied."
                    ),
                    alertClass: "alert-warning",
                },
                processing_fee_refunded: {
                    text: $__(
                        "A refund for the lost item processing charge has been applied to the borrowing patron's account."
                    ),
                    alertClass: "alert-info",
                },
                lost_item_fee_remains: {
                    text: $__(
                        "Any lost item fees for this item will remain on the patron's account."
                    ),
                    alertClass: "alert-warning",
                },
                processing_fee_remains: {
                    text: $__(
                        "Any processing fees for this item will remain on the patron's account."
                    ),
                    alertClass: "alert-warning",
                },
                was_lost: {
                    text: $__("Item was lost, now found."),
                    alertClass: "alert-info",
                },
                indefinitely_debarred: {
                    text: $__(
                        "Reminder: Patron has an indefinite restriction."
                    ),
                    alertClass: "alert-warning",
                },
            };
            // Only one lost item fee outcome is shown, like the legacy page
            const lostFeeOutcomes = [
                "lost_item_fee_refunded",
                "lost_item_fee_charged",
                "lost_item_fee_restored",
                "lost_item_payment_not_refunded",
            ];
            const lostFeeOutcome = lostFeeOutcomes.find(code =>
                messages.some(m => m.message === code)
            );
            // Patron note recorded on the checkout (issues.note)
            if (latest.checkout?.note) {
                detailed.push({
                    text:
                        `<h4>${escapeHtml($__("Patron note"))}</h4>` +
                        (latest.checkout.note_date
                            ? `<p>${escapeHtml(formatDate(latest.checkout.note_date))}</p>`
                            : "") +
                        `<p>${escapeHtml(latest.checkout.note)}</p>`,
                    alertClass: "alert-info issue-note",
                });
            }
            // Restriction end dates, formatted like the legacy page
            const restrictionMessages = {
                debarred: [
                    $__("Patron is now restricted until %s."),
                    $__("Patron is now restricted."),
                ],
                previously_debarred: [
                    $__("Reminder: Patron was earlier restricted until %s."),
                    $__("Reminder: Patron was earlier restricted."),
                ],
            };
            for (const msg of messages) {
                if (restrictionMessages[msg.message]) {
                    const [withDate, withoutDate] =
                        restrictionMessages[msg.message];
                    const until = msg.payload?.until;
                    detailed.push({
                        text: until
                            ? withDate.replace(
                                  "%s",
                                  escapeHtml(formatDate(until))
                              )
                            : withoutDate,
                        alertClass: "alert-warning",
                    });
                }
                if (
                    feeMessages[msg.message] &&
                    (!lostFeeOutcomes.includes(msg.message) ||
                        msg.message === lostFeeOutcome)
                ) {
                    detailed.push(feeMessages[msg.message]);
                }
                if (
                    msg.message === "in_bundle" &&
                    msg.payload &&
                    !removedFromBundle.value.has(latest.checkin_id)
                ) {
                    detailed.push({
                        text: $__(
                            'This item belongs to a bundle: <a href="/cgi-bin/koha/catalogue/detail.pl?biblionumber=%s">%s</a> <button type="button" class="btn btn-default btn-xs remove-from-bundle" data-checkin-id="%s" data-item-id="%s" data-host-item-id="%s"><i class="fa fa-minus"></i> Remove from bundle</button>'
                        )
                            .replace(
                                "%s",
                                escapeHtml(msg.payload.host_biblio_id)
                            )
                            .replace(
                                "%s",
                                escapeHtml(msg.payload.host_external_id)
                            )
                            .replace("%s", escapeHtml(latest.checkin_id))
                            .replace("%s", escapeHtml(latest.item?.item_id))
                            .replace(
                                "%s",
                                escapeHtml(msg.payload.host_item_id)
                            ),
                        alertClass: "alert-warning",
                    });
                }
                if (
                    (msg.message === "bundle_missing_items" ||
                        msg.message === "bundle_unexpected_items") &&
                    msg.payload
                ) {
                    const heading =
                        msg.message === "bundle_missing_items"
                            ? $__(
                                  "Bundle had missing items, they have been marked as lost:"
                              )
                            : $__(
                                  "Bundle had unexpected items, they have been removed from the bundle. Please place them to one side:"
                              );
                    const items = (msg.payload.items || [])
                        .map(
                            i =>
                                `<li>${escapeHtml(i.title)} - ${escapeHtml(i.external_id)}</li>`
                        )
                        .join("");
                    detailed.push({
                        text: `<strong>${escapeHtml(heading)}</strong><ul>${items}</ul>`,
                        alertClass: "alert-warning",
                    });
                }
                if (msg.message === "hold_auto_filled" && msg.payload) {
                    const p = latest.hold?.patron;
                    const holdPatron = p
                        ? p.firstname
                            ? `${p.surname}, ${p.firstname}`
                            : p.surname
                        : "";
                    const destination =
                        store.libraries[msg.payload.library_id] ||
                        msg.payload.library_id;
                    const transfer =
                        msg.payload.library_id !== latest.library_id;
                    detailed.push({
                        text:
                            `<strong>${escapeHtml($__("Hold filled for:"))}</strong> ${escapeHtml(holdPatron)}<br>` +
                            `<strong>${escapeHtml(transfer ? $__("Transfer to:") : $__("Hold at"))}</strong> ${escapeHtml(destination)} ` +
                            `<button type="button" class="btn btn-default btn-xs print-hold-slip" data-reserve-id="${escapeHtml(msg.payload.reserve_id)}"><i class="fa fa-print"></i> ${escapeHtml($__("Print"))}</button>`,
                        alertClass: "alert-info hold-auto-filled",
                    });
                }
                if (
                    msg.message === "not_for_loan_status_updated" &&
                    msg.payload
                ) {
                    detailed.push({
                        text: escapeHtml(notForLoanUpdateText(msg.payload)),
                        alertClass: "alert-warning",
                    });
                }
                if (msg.message === "item_location_updated" && msg.payload) {
                    detailed.push({
                        text: escapeHtml(
                            $__(
                                "Item shelving location updated. Old value: %s. New value: %s."
                            )
                                .replace(
                                    "%s",
                                    avDescription("LOC", msg.payload.from)
                                )
                                .replace(
                                    "%s",
                                    avDescription("LOC", msg.payload.to)
                                )
                        ),
                        alertClass: "alert-warning",
                    });
                }
                if (msg.message === "item_type_checkinmsg" && msg.payload) {
                    detailed.push({
                        text: msg.payload.text,
                        alertClass:
                            msg.type === "alert"
                                ? "alert-warning"
                                : "alert-info",
                    });
                }
                if (msg.message === "patron_has_fines" && msg.payload) {
                    detailed.push({
                        text: $__(
                            'Patron has outstanding fines of %s. <a href="/cgi-bin/koha/members/pay.pl?borrowernumber=%s">Make payment</a>'
                        )
                            .replace("%s", escapeHtml(msg.payload.balance))
                            .replace("%s", escapeHtml(msg.payload.patron_id)),
                        alertClass: "alert-warning",
                    });
                }
                if (msg.message === "patron_has_waiting_holds" && msg.payload) {
                    const p = latest.checkout && latest.checkout.patron;
                    const patronName = escapeHtml(
                        p
                            ? p.firstname
                                ? `${p.surname}, ${p.firstname}`
                                : p.surname
                            : $__("Patron")
                    );
                    detailed.push({
                        text: $__(
                            '%s has %s hold(s) waiting for pickup. <a href="/cgi-bin/koha/circ/circulation.pl?borrowernumber=%s">Check out to this patron</a>'
                        )
                            .replace("%s", patronName)
                            .replace(
                                "%s",
                                escapeHtml(msg.payload.waiting_count)
                            )
                            .replace("%s", escapeHtml(msg.payload.patron_id)),
                        alertClass: "alert-info",
                        priority: 10,
                    });
                }
                // return_claim is handled by the row (yellow + resolve button)
                // No alert needed
                if (msg.message === "claim_auto_resolved") {
                    detailed.push({
                        text: $__(
                            "Previously claimed returned item has been checked in. Claim automatically resolved."
                        ),
                        alertClass: "alert-info",
                    });
                }
            }
            // Show the most important alerts first (e.g. waiting holds), while
            // keeping the original order for boxes of equal priority.
            return detailed
                .map((box, index) => ({ box, index }))
                .sort(
                    (a, b) =>
                        (b.box.priority || 0) - (a.box.priority || 0) ||
                        a.index - b.index
                )
                .map(entry => entry.box);
        });

        function avDescription(category, value) {
            if (value === undefined || value === null || value === "") {
                return $__("Available for loan");
            }
            return store.authorisedValues[category]?.[value] || value;
        }

        // Mirrors the legacy UpdateNotForLoanStatusOnCheckin message
        function notForLoanUpdateText(payload) {
            if (payload.to === "ONLYMESSAGE") {
                return avDescription("NOT_LOAN", payload.from);
            }
            return $__(
                "Not for loan status updated. Old value: %s. New value: %s."
            )
                .replace("%s", avDescription("NOT_LOAN", payload.from))
                .replace("%s", avDescription("NOT_LOAN", payload.to));
        }

        // Refocus barcode input when focus leaves to non-interactive elements
        // (e.g., sidebar toggle button, page chrome clicks)
        function handleDocumentClick(e) {
            // Refocus only when the sidebar collapse toggle is clicked
            if (e.target.closest(".sidebar-toggle")) {
                nextTick(() => refocusInput());
            }
        }

        onMounted(() => {
            document.addEventListener("click", handleDocumentClick);
            handleUrlParams();
        });

        // Handle deep-link query params carried over from the legacy
        // returns.pl page so existing links keep working:
        //   ?barcode=XXXX   -> auto-submit a checkin
        function handleUrlParams() {
            const params = new URLSearchParams(window.location.search);

            const barcode = params.get("barcode");
            if (barcode && barcode.trim()) {
                onBarcodeScan(barcode.trim());
            }
        }

        onBeforeUnmount(() => {
            document.removeEventListener("click", handleDocumentClick);
        });

        // Watch for new pending items — auto-show panel for the first one
        watch(nextModalItem, newItem => {
            if (newItem && !activeModalItem.value) {
                activeModalItem.value = newItem;
                nextTick(() => refocusInput());
            }
        });

        function onBarcodeScan(barcode) {
            // Moving on from a non-blocking transfer confirms it when
            // AutomaticConfirmTransfer is set (legacy: on closing the modal)
            const active = activeModalItem.value;
            if (
                active &&
                active._action_type === "transfer" &&
                policy.value.auto_confirm_transfer &&
                !policy.value.transfers_block
            ) {
                onResolve(active, "confirm_transfer");
            }

            // Fire and forget — don't block the input
            store.checkin(barcode, { ...checkinOptions }).then(result => {
                // HoldsAutoFillPrintSlip: print the slip for an auto-filled hold
                const autoFilled = (result?.data?.messages || []).find(
                    m => m.message === "hold_auto_filled"
                );
                if (
                    autoFilled &&
                    result.status === "success" &&
                    policy.value.holds_auto_fill_print_slip
                ) {
                    printHoldSlip(autoFilled.payload.reserve_id);
                }
            });
            // Clear return date if "remember" is not checked
            if (checkinOptionsRef.value) {
                checkinOptionsRef.value.afterCheckin();
            }
            nextTick(() => refocusInput());
        }

        function showModalFor(item) {
            activeModalItem.value = item;
        }

        function onMessagesClick(e) {
            const btn = e.target.closest(".resolve-claim-btn");
            if (btn) {
                activeClaimId.value = parseInt(btn.dataset.claimId);
                showClaimModal.value = true;
            }
            const slipBtn = e.target.closest(".print-hold-slip");
            if (slipBtn) {
                printHoldSlip(slipBtn.dataset.reserveId);
            }
            const bundleBtn = e.target.closest(".remove-from-bundle");
            if (bundleBtn) {
                removeFromBundle(bundleBtn.dataset);
            }
        }

        async function removeFromBundle({ checkinId, itemId, hostItemId }) {
            try {
                const response = await fetch(
                    `/api/v1/items/${hostItemId}/bundled_items/${itemId}`,
                    { method: "DELETE" }
                );
                if (!response.ok) throw new Error(response.statusText);
                removedFromBundle.value = new Set([
                    ...removedFromBundle.value,
                    parseInt(checkinId),
                ]);
            } catch (e) {
                lastError.value = $__(
                    "Could not remove the item from the bundle"
                );
            }
        }

        function onResolveClaimFromRow(checkin) {
            const claimMsg = (checkin.messages || []).find(
                m => m.message === "return_claim"
            );
            if (claimMsg && claimMsg.payload) {
                activeClaimId.value = claimMsg.payload.claim_id;
                showClaimModal.value = true;
            }
        }

        function onResolveClaimFromModal(item) {
            // Close the confirmation modal and open the resolve claim modal
            activeModalItem.value = null;
            const claimMsg = (item.messages || []).find(
                m => m.message === "return_claim"
            );
            if (claimMsg && claimMsg.payload) {
                activeClaimId.value = claimMsg.payload.claim_id;
                showClaimModal.value = true;
            }
        }

        function onClaimResolved() {
            showClaimModal.value = false;
            // Mark the claim row as resolved
            const idx = checkins.value.findIndex(
                c => c._action_type === "claim" && c._status === "needs_action"
            );
            if (idx !== -1) {
                checkins.value[idx] = {
                    ...checkins.value[idx],
                    _status: "success",
                    _action_type: null,
                };
            }
            activeClaimId.value = null;
        }

        async function onConfirm(item) {
            // For bundle items, show the verification modal instead of confirming directly
            if (item._confirms && item._confirms.items_bundle) {
                activeModalItem.value = null;
                bundleItemId.value = item.item?.item_id || null;
                bundleBarcode.value =
                    item._barcode || item.item?.external_id || "";
                showBundleModal.value = true;
                // Store the item for later confirmation
                _pendingBundleItem = item;
                return;
            }
            await store.confirmPending(item);
            _advanceModal();
        }

        let _pendingBundleItem = null;

        async function onBundleConfirm(result) {
            showBundleModal.value = false;
            if (_pendingBundleItem) {
                // Pass verified barcodes through options — they will be
                // included in the POST /checkins body alongside the JWT
                if (result.verify) {
                    _pendingBundleItem._options.verified_bundle_barcodes =
                        result.scanned || [];
                }
                await store.confirmPending(_pendingBundleItem);
                _pendingBundleItem = null;
            }
            _advanceModal();
        }

        function onDismiss(item) {
            store.dismissPending(item);
            _advanceModal();
        }

        function onIgnore(item) {
            store.ignoreAction(item);
            _advanceModal();
        }

        // A non-blocking transfer modal was closed without picking an
        // action. Legacy confirmed an existing transfer on closing when
        // AutomaticConfirmTransfer was set, and left it alone otherwise.
        function onClose(item) {
            // Another modal was opened by the same click
            if (activeModalItem.value !== item) return;
            if (item.transfer_id && policy.value.auto_confirm_transfer) {
                onResolve(item, "confirm_transfer");
            } else {
                onIgnore(item);
            }
        }

        async function onResolve(item, action, params = {}) {
            const result = await store.resolveAction(item, action, params);
            const slip = params.slip;
            if (slip?.window) {
                if (result.status === "ok") {
                    slip.window.location.href = slip.url;
                } else {
                    slip.window.close();
                }
            }
            _advanceModal();
        }

        // Open the secondary hold-cancellation pop-up for the active item
        function onOpenCancelHold(item) {
            holdCancellationItem.value = item;
            showHoldCancellationModal.value = true;
        }

        // Confirm from the secondary pop-up: cancel the hold via the API and
        // resolve the main modal
        async function onConfirmHoldCancellation(params = {}) {
            const item = holdCancellationItem.value;
            showHoldCancellationModal.value = false;
            holdCancellationItem.value = null;
            if (!item) return;
            await store.resolveAction(item, "cancel_hold", {
                ...params,
                forgive_hold_fees: checkinOptions.forgive_hold_fees,
            });
            _advanceModal();
        }

        function _advanceModal() {
            activeModalItem.value = null;
            setTimeout(() => {
                if (nextModalItem.value) {
                    activeModalItem.value = nextModalItem.value;
                } else {
                    refocusInput();
                }
            }, 100);
        }

        function refocusInput() {
            if (barcodeInputRef.value) {
                barcodeInputRef.value.focus();
            }
        }

        return {
            checkins,
            processing,
            lastError,
            pendingItems,
            activeModalItem,
            isInputBlocked,
            hasActiveSettings,
            dropboxDate,
            formatDate,
            lastCheckinMessages,
            showOptions,
            showClaimModal,
            activeClaimId,
            showBundleModal,
            bundleItemId,
            bundleBarcode,
            showHoldCancellationModal,
            onOpenCancelHold,
            onConfirmHoldCancellation,
            barcodeInputRef,
            checkinOptionsRef,
            checkinOptions,
            onOptionsUpdate,
            onBarcodeScan,
            showModalFor,
            onMessagesClick,
            onResolveClaimFromRow,
            onResolveClaimFromModal,
            onClaimResolved,
            onBundleConfirm,
            onConfirm,
            onClose,
            onDismiss,
            onIgnore,
            onResolve,
            $__,
        };
    },
};
</script>
