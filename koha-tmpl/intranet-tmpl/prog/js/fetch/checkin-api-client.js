// Follow-up actions require the token returned for them in the checkin's
// action_tokens attribute
const withActionToken = (endpoint, action_token) =>
    `${endpoint}?action_token=${encodeURIComponent(action_token || "")}`;

export class CheckinAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/",
        });
    }

    get checkins() {
        return {
            create: (body, params = {}) =>
                this.httpClient.post({
                    endpoint:
                        "checkins" +
                        (params.confirmation
                            ? `?confirmation=${params.confirmation}`
                            : ""),
                    body,
                    headers: {
                        "x-koha-embed":
                            "item+strings,item.biblio,checkout,checkout.patron,checkout.patron.checkouts+count,hold,hold.patron+strings,hold.patron.notification_summary,transfer,recall,recall.patron+strings,recall.patron.notification_summary",
                        "x-koha-override": "not_issued",
                    },
                    return_response: true,
                    return_error_response: true,
                    mark_submitting: false,
                }),
            confirmHold: (checkin_id, { action_token } = {}) =>
                this.httpClient.post({
                    endpoint: withActionToken(
                        `checkins/${checkin_id}/hold_confirmation`,
                        action_token
                    ),
                    headers: {
                        "x-koha-embed": "item,hold,hold.patron,transfer",
                    },
                }),
            cancelHold: (
                checkin_id,
                { reason, forgive_hold_fees, action_token } = {}
            ) =>
                this.httpClient.post({
                    endpoint: withActionToken(
                        `checkins/${checkin_id}/hold_cancellation`,
                        action_token
                    ),
                    body: {
                        ...(reason ? { reason } : {}),
                        ...(forgive_hold_fees
                            ? { forgive_hold_fees: true }
                            : {}),
                    },
                    headers: {
                        "x-koha-embed": "item,hold",
                    },
                    // The caller handles errors: a refusal carries the
                    // current module policy
                    return_response: true,
                    return_error_response: true,
                }),
            confirmTransfer: (
                checkin_id,
                { to_library_id, reason, action_token } = {}
            ) =>
                this.httpClient.post({
                    endpoint: withActionToken(
                        `checkins/${checkin_id}/transfer_confirmation`,
                        action_token
                    ),
                    body: {
                        ...(to_library_id ? { to_library_id } : {}),
                        ...(reason ? { reason } : {}),
                    },
                    headers: {
                        "x-koha-embed": "item,transfer,transfer.to_library",
                    },
                }),
            cancelTransfer: (checkin_id, { action_token } = {}) =>
                this.httpClient.post({
                    endpoint: withActionToken(
                        `checkins/${checkin_id}/transfer_cancellation`,
                        action_token
                    ),
                    headers: {
                        "x-koha-embed": "item",
                    },
                }),
            confirmRecall: (checkin_id, { action_token } = {}) =>
                this.httpClient.post({
                    endpoint: withActionToken(
                        `checkins/${checkin_id}/recall_confirmation`,
                        action_token
                    ),
                    headers: {
                        "x-koha-embed": "item,recall,recall.patron",
                    },
                }),
        };
    }
}

export default CheckinAPIClient;
