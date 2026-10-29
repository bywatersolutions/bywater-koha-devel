export class PatronAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/",
        });
    }

    get patrons() {
        return {
            get: id =>
                this.httpClient.get({
                    endpoint: "patrons/" + id,
                }),
        };
    }

    get hold_groups() {
        return {
            cancel: (patron_id, hold_group_id, { cancellation_reason } = {}) =>
                this.httpClient.post({
                    endpoint: `patrons/${patron_id}/hold_groups/${hold_group_id}/cancel`,
                    body: {
                        ...(cancellation_reason ? { cancellation_reason } : {}),
                    },
                    // 204 No Content: there is no JSON body to parse
                    return_response: true,
                }),
        };
    }

    get categories() {
        return {
            getAll: (query, params, headers) =>
                this.httpClient.getAll({
                    endpoint: "patron_categories",
                    query,
                    params,
                    headers,
                }),
        };
    }

    get self_renewal() {
        return {
            start: (id, query, params, headers) =>
                this.httpClient.getAll({
                    endpoint: `public/patrons/${id}/self_renewal`,
                    query,
                    params,
                    headers,
                }),
            submit: (id, renewal) =>
                this.httpClient.post({
                    endpoint: `public/patrons/${id}/self_renewal`,
                    body: renewal,
                }),
        };
    }
}

export default PatronAPIClient;
