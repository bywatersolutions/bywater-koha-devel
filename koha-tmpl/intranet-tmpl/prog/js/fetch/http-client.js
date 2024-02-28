class Dialog {
    constructor(options = {}) {}

    setMessage(message) {
        $("#messages").append(
            '<div class="dialog message">%s</div>'.format(message)
        );
    }

    setError(error) {
        $("#messages").append(
            '<div class="dialog alert">%s</div>'.format(error)
        );
    }
}

class HttpClient {
    constructor(options = {}) {
        this._baseURL = options.baseURL || "";
        this._headers = options.headers || { // FIXME we actually need to merge the headers
            "Content-Type": "application/json;charset=utf-8",
            "X-Requested-With": "XMLHttpRequest"
        };
        this.csrf_token = $('meta[name="csrf-token"]').attr("content");
    }

    async _fetchJSON(
        endpoint,
        headers = {},
        options = {},
        return_response = false,
        mark_submitting = false
    ) {
        let res, error;
        //if (mark_submitting) submitting();
        await fetch(this._baseURL + endpoint, {
            ...options,
            headers: { ...this._headers, ...headers },
        })
            .then(response => {
                if (!response.ok) {
                    return response.text().then(text => {
                        let message;
                        if (text) {
                            let json = JSON.parse(text);
                            message =
                                json.error ||
                                json.errors.map(e => e.message).join("\n") ||
                                json;
                        } else {
                            message = response.statusText;
                        }
                        throw new Error(message);
                    });
                }
                return return_response ? response : response.json();
            })
            .then(result => {
                res = result;
            })
            .catch(err => {
                error = err;
                new Dialog().setError(err);
                console.error(err);
            })
            .then(() => {
                //if (mark_submitting) submitted();
            });

        if (error) throw Error(error);

        return res;
    }

    post(params = {}) {
        const body = params.body
            ? typeof params.body === "string"
                ? params.body
                : JSON.stringify(params.body)
            : params.data || undefined;
        let csrf_token = { csrf_token: this.csrf_token };
        let headers = { ...csrf_token, ...params.headers };
        return this._fetchJSON(
            params.endpoint,
            headers,
            {
                ...params.options,
                body,
                method: "POST",
            },
            false,
            true
        );
    }
}

export default HttpClient;
