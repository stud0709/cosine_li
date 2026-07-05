const sdk = require('../sap-dev/references/sap-dev-sdk');

function parseXml(xml) {
    const result = {};
    const regex = /<([A-Z0-9_]+)>([^<]*)<\/\1>/g;
    let match;
    while ((match = regex.exec(xml)) !== null) {
        result[match[1]] = match[2].trim();
    }
    return result;
}

async function run() {
    sdk.validateEnv();

    try {
        const response = await fetch(`${sdk.env.url.replace(/\/$/, '')}/api/guarded/request`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${sdk.env.token}`
            },
            body: JSON.stringify({
                method: 'GET',
                uri: '/sap/public/info',
                bypass_api_guard: false
            })
        });

        if (!response.ok) {
            const errText = await response.text();
            let parsedErr;
            try {
                parsedErr = JSON.parse(errText);
            } catch (e) {}
            const errMsg = (parsedErr && parsedErr.detail) || errText || `HTTP ${response.status}`;
            throw new Error(errMsg);
        }

        const contentType = response.headers.get('content-type') || '';
        const bodyText = await response.text();

        let resultData;
        if (contentType.includes('xml') || bodyText.trim().startsWith('<')) {
            resultData = parseXml(bodyText);
        } else {
            try {
                resultData = JSON.parse(bodyText);
            } catch (e) {
                resultData = { raw: bodyText };
            }
        }

        sdk.success(resultData);

    } catch (err) {
        sdk.fail(`Failed to fetch /sap/public/info: ${err.message}`);
    }
}

run();
