/**
 * API client for the system messages endpoints.
 */
export class SystemMessageAPIClient {
    /**
     * @param {typeof import("./http-client.js").default} HttpClient the HTTP client class to use
     */
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/system_messages",
        });
    }

    /**
     * System message operations.
     *
     * @returns {{clear: function(number): Promise<object>, clear_all: function(): Promise<object>}}
     */
    get system_messages() {
        return {
            /**
             * Clears one system message.
             *
             * @param {number} id the system message identifier
             * @returns {Promise<object>} the cleared system message
             */
            clear: id =>
                this.httpClient.put({
                    endpoint: "/" + id + "/clear",
                }),
            /**
             * Clears every uncleared system message.
             *
             * @returns {Promise<object>} resolves when the messages are cleared
             */
            clear_all: () =>
                this.httpClient.put({
                    endpoint: "/clear",
                }),
        };
    }
}

export default SystemMessageAPIClient;
