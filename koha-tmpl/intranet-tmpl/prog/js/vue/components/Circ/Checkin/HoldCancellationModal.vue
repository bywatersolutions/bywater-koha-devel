<template>
    <div
        v-if="visible"
        class="modal show d-block"
        tabindex="-1"
        role="dialog"
    >
        <div class="modal-dialog modal-sm">
            <div class="modal-content">
                <div class="modal-header">
                    <h1 class="modal-title">
                        {{ $__("Cancel hold") }}
                    </h1>
                </div>
                <div class="modal-body">
                    <div class="mb-3">
                        <label for="hold-cancellation-reason" class="form-label">
                            {{ $__("Cancellation reason:") }}
                        </label>
                        <select
                            id="hold-cancellation-reason"
                            v-model="reason"
                            class="form-select"
                        >
                            <option value="">
                                {{ $__("No reason given") }}
                            </option>
                            <option
                                v-for="r in reasons"
                                :key="r.authorised_value"
                                :value="r.authorised_value"
                            >
                                {{ r.description }}
                            </option>
                        </select>
                    </div>
                </div>
                <div class="modal-footer">
                    <button
                        type="button"
                        class="btn btn-danger"
                        :disabled="cancelling"
                        @click="confirm"
                    >
                        <i class="fa fa-trash-can"></i>
                        {{ $__("Cancel hold") }}
                    </button>
                    <button
                        type="button"
                        class="btn btn-default"
                        :disabled="cancelling"
                        @click="$emit('close')"
                    >
                        {{ $__("Keep hold") }}
                    </button>
                </div>
            </div>
        </div>
    </div>
    <div v-if="visible" class="modal-backdrop show"></div>
</template>

<script>
import { onMounted, ref } from "vue";
import { APIClient } from "../../../fetch/api-client.js";
import { $__ } from "@koha-vue/i18n";

export default {
    props: {
        visible: {
            type: Boolean,
            default: false,
        },
        cancelling: {
            type: Boolean,
            default: false,
        },
    },
    emits: ["confirm", "close"],
    setup(props, { emit }) {
        const reason = ref("");
        const reasons = ref([]);

        onMounted(() => {
            // Fetch HOLD_CANCELLATION authorised values
            APIClient.authorised_values.values
                .get("HOLD_CANCELLATION")
                .then(values => {
                    reasons.value = values || [];
                })
                .catch(() => {});
        });

        function confirm() {
            emit("confirm", { reason: reason.value || undefined });
        }

        return {
            reason,
            reasons,
            confirm,
            $__,
        };
    },
};
</script>
