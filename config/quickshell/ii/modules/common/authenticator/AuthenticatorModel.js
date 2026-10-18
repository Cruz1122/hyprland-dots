.pragma library

function key(account) {
    return account.issuer + "\u0000" + account.account;
}

function normalizeAccount(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const issuer = String(value.issuer || "").trim();
    const account = String(value.account || "").trim();
    const secret = String(value.secret || "").replace(/\s/g, "").toUpperCase();
    const digits = Number(value.digits === undefined ? 6 : value.digits);
    const period = Number(value.period === undefined ? 30 : value.period);
    const algorithm = String(value.algorithm || "SHA1").toUpperCase();
    if (!account || account.length > 1024 || issuer.length > 1024 || /\u0000/.test(issuer + account)) return null;
    if (!secret || secret.length > 512 || !/^[A-Z2-7]+$/.test(secret) || [1, 3, 6].includes(secret.length % 8)) return null;
    if (![6, 8].includes(digits) || !Number.isInteger(period) || period < 1 || period > 3600) return null;
    if (!["SHA1", "SHA256", "SHA512"].includes(algorithm)) return null;
    return { issuer: issuer, account: account, secret: secret, digits: digits, period: period, algorithm: algorithm };
}

function loadAccounts(text) {
    const values = JSON.parse(text || "[]");
    if (!Array.isArray(values)) throw new Error("Invalid account collection");
    const result = [];
    const indices = Object.create(null);
    values.forEach(value => {
        const account = normalizeAccount(value);
        if (!account) throw new Error("Invalid saved account");
        const accountKey = key(account);
        if (indices[accountKey] !== undefined) result[indices[accountKey]] = account;
        else { indices[accountKey] = result.length; result.push(account); }
    });
    return result;
}

function displayEntries(accounts) {
    // Deliberately omit the secret and all storage/process metadata from the UI model.
    return accounts.map(account => ({ key: key(account), issuer: account.issuer,
        account: account.account, digits: account.digits, period: account.period }));
}

function windowSignature(accounts, now) {
    return JSON.stringify(accounts.map(account => Math.floor(now / account.period)));
}

function remainingFraction(period, now) {
    if (!Number.isFinite(period) || period <= 0 || !Number.isFinite(now)) return 0;
    return 1 - ((now % period + period) % period) / period;
}

function currentCode(entry, codes, generatedAt, now) {
    if (generatedAt < 0 || Math.floor(generatedAt / entry.period) !== Math.floor(now / entry.period)) return "";
    const code = codes[entry.key];
    return typeof code === "string" && new RegExp("^[0-9]{" + entry.digits + "}$").test(code) ? code : "";
}

function formattedCode(code) {
    if (!/^(?:[0-9]{6}|[0-9]{8})$/.test(code)) return "··· ···";
    const middle = code.length / 2;
    return code.slice(0, middle) + " " + code.slice(middle);
}
