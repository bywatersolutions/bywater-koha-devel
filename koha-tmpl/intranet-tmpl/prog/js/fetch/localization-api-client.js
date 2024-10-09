export class LocalizationAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/cgi-bin/koha/svc/localization",
        });
    }

    get localizations() {
        return {
            create: localization =>
                this.httpClient.post({
                    endpoint: "",
                    body: new URLSearchParams(localization).toString(),
                    headers: {
                        "Content-Type":
                            "application/x-www-form-urlencoded;charset=utf-8",
                    },
                }),
            update: localization =>
                this.httpClient.put({
                    endpoint: "",
                    body: new URLSearchParams(localization).toString(),
                    headers: {
                        "Content-Type":
                            "application/x-www-form-urlencoded;charset=utf-8",
                    },
                }),
            delete: localization =>
                this.httpClient.delete({
                    endpoint:
                        "?" + new URLSearchParams(localization).toString(),
                }),
        };
    }
}

export default LocalizationAPIClient;
