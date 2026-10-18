import { test } from "node:test";
import assert from "node:assert/strict";
import { readUsage } from "../config/quickshell/ii/browser-extension/usage.mjs";

test("Cursor exports whitelisted usage and hashed identity, not credentials or user data", async () => {
  const requested = [];
  const request = async (url, options) => {
    requested.push(url);
    assert.equal(options.credentials, "include");
    assert.equal(options.redirect, "error");
    return Response.json(url.endsWith("auth/me") ? { id: "synthetic-user", email: "CANARY_EMAIL", accessToken: "CANARY_TOKEN" }
      : { individualUsage: { plan: { totalPercentUsed: 25, secret: "CANARY_SECRET" } }, unrelated: "CANARY_OTHER" });
  };
  const result = await readUsage("cursor", "https://cursor.com", request);
  assert.equal(result.status, "ready");
  assert.equal(result.usage.individualUsage.plan.totalPercentUsed, 25);
  assert.match(result.identity, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(JSON.stringify(result), /CANARY|synthetic-user/);
  assert.deepEqual(requested, ["/api/auth/me", "/api/usage-summary", "/api/auth/me"]);
});

test("wrong origins never issue an authenticated request", async () => {
  const result = await readUsage("cursor", "https://evil.invalid", () => assert.fail("network must not run"));
  assert.equal(result.status, "wrong-origin");
});

test("Cursor account switch discards usage", async () => {
  let count = 0;
  const result = await readUsage("cursor", "https://cursor.com", async () => Response.json(
    ++count === 1 ? { id: "A" } : count === 2 ? { individualUsage: { plan: { totalPercentUsed: 99 } } } : { id: "B" }));
  assert.deepEqual(result, { status: "account-changed" });
});

test("Cursor usage succeeds with an active session when auth omits a stable identity", async () => {
  const result = await readUsage("cursor", "https://cursor.com", async url => Response.json(
    url.endsWith("auth/me") ? { authenticated: true } : { individualUsage: { plan: { totalPercentUsed: 37 } } }));
  assert.equal(result.status, "ready");
  assert.equal(result.identity, null);
  assert.equal(result.usage.individualUsage.plan.totalPercentUsed, 37);
});

test("Cursor identity envelope and numeric IDs are normalized before comparing sessions", async () => {
  let count = 0;
  const result = await readUsage("cursor", "https://cursor.com", async url => {
    count++;
    return Response.json(url.endsWith("auth/me")
      ? { user: { id: 123 } }
      : { individualUsage: { plan: { totalPercentUsed: 12 } } });
  });
  assert.equal(result.status, "ready");
  assert.match(result.identity, /^[a-f0-9]{64}$/);
  assert.equal(count, 3);
});

test("Cursor envelope changes do not masquerade as an account switch", async () => {
  let authReads = 0;
  const result = await readUsage("cursor", "https://cursor.com", async url => {
    if (url.endsWith("auth/me")) return Response.json(++authReads === 1 ? { id: "same-user" } : { user: { id: "same-user" } });
    return Response.json({ individualUsage: { plan: { totalPercentUsed: 28 } } });
  });
  assert.equal(result.status, "ready");
  assert.equal(result.identity, null);
  assert.equal(result.usage.individualUsage.plan.totalPercentUsed, 28);
});

test("Cursor rejects a changed identity at the same explicit field path", async () => {
  let authReads = 0;
  const result = await readUsage("cursor", "https://cursor.com", async url => {
    if (url.endsWith("auth/me")) return Response.json({ user: { id: ++authReads === 1 ? "user-A" : "user-B" } });
    return Response.json({ individualUsage: { plan: { totalPercentUsed: 28 } } });
  });
  assert.deepEqual(result, { status: "account-changed" });
});

test("Cursor session expiry during the usage read is not accepted as an unverified success", async () => {
  let authReads = 0;
  const result = await readUsage("cursor", "https://cursor.com", async url => {
    if (url.endsWith("auth/me") && ++authReads === 2) return new Response("", { status: 401 });
    return Response.json(url.endsWith("auth/me") ? { user: { id: "A" } }
      : { individualUsage: { plan: { totalPercentUsed: 28 } } });
  });
  assert.deepEqual(result, { status: "login-required" });
});

test("a value moving between unrelated identity fields does not mask a shared-field account switch", async () => {
  let authReads = 0;
  const result = await readUsage("cursor", "https://cursor.com", async url => {
    if (url.endsWith("auth/me")) return Response.json(++authReads === 1
      ? { user: { id: "A", sub: "S" } } : { user: { id: "B", sub: "A" } });
    return Response.json({ individualUsage: { plan: { totalPercentUsed: 28 } } });
  });
  assert.deepEqual(result, { status: "account-changed" });
});

test("executeScript-style serialization works without module-scope bindings", async () => {
  const injected = new Function(`return (${readUsage.toString()})`)();
  const result = await injected("cursor", "https://cursor.com", async url => Response.json(
    url.endsWith("auth/me") ? { user: { id: 123 } }
      : { individualUsage: { plan: { totalPercentUsed: 41 } } }));
  assert.equal(result.status, "ready");
  assert.equal(result.usage.individualUsage.plan.totalPercentUsed, 41);
  assert.match(result.identity, /^[a-f0-9]{64}$/);
});

test("Zed reads billing using dashboard credentials with only quota fields leaving the browser", async () => {
  const result = await readUsage("zed", "https://dashboard.zed.dev", async url => {
    assert.equal(url, "https://cloud.zed.dev/frontend/billing/usage");
    return Response.json({ current_usage: { token_spend: { spend_in_cents: 300, limit_in_cents: 4200, secret: "CANARY" } } });
  });
  assert.deepEqual(result, { status: "ready", identity: null,
    usage: { current_usage: { token_spend: { spend_in_cents: 300, limit_in_cents: 4200 } } } });
});

test("expired sessions, unavailable responses and oversized bodies do not claim success", async () => {
  assert.equal((await readUsage("zed", "https://zed.dev", async () => new Response("", { status: 401 }))).status, "login-required");
  assert.equal((await readUsage("zed", "https://zed.dev", async () => new Response("CANARY", { status: 500 }))).status, "unavailable");
  assert.equal((await readUsage("zed", "https://zed.dev", async () => new Response("x".repeat(1048577)))).status, "unavailable");
});
