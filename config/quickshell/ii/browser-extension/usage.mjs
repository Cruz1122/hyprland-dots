// Self-contained: Chrome serializes this function into an isolated provider-tab world.
export async function readUsage(provider, origin = location.origin, request = fetch) {
  function cursorIdentities(value) {
    const result = new Map();
    if (!value || typeof value !== "object") return result;
    for (const [path, candidate] of [["", value], ["user.", value.user], ["account.", value.account]]) {
      if (!candidate || typeof candidate !== "object") continue;
      for (const key of ["id", "userId", "sub"]) {
        const principal = candidate[key];
        if ((typeof principal === "string" && principal.length > 0) ||
            (typeof principal === "number" && Number.isSafeInteger(principal)))
          result.set(path + key, String(principal));
      }
    }
    return result;
  }
  const allowed = provider === "cursor" ? ["https://cursor.com"]
    : provider === "zed" ? ["https://zed.dev", "https://dashboard.zed.dev"] : [];
  if (!allowed.includes(origin)) return { status: "wrong-origin" };
  const get = async url => {
    const response = await request(url, { credentials: "include", redirect: "error", signal: AbortSignal.timeout(10000) });
    if (response.status === 401 || response.status === 403) return null;
    if (!response.ok) throw Error("unavailable");
    const reader = response.body.getReader();
    const chunks = []; let size = 0;
    try {
      while (true) {
        const next = await reader.read(); if (next.done) break;
        size += next.value.length; if (size > 1048576) throw Error("too-large");
        chunks.push(next.value);
      }
    } finally { await reader.cancel(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(bytes));
  };
  try {
    if (provider === "cursor") {
      const before = await get("/api/auth/me"); if (!before) return { status: "login-required" };
      const data = await get("/api/usage-summary"); if (!data) return { status: "login-required" };
      const after = await get("/api/auth/me");
      if (!after) return { status: "login-required" };
      const beforeIdentities = cursorIdentities(before);
      const afterIdentities = cursorIdentities(after);
      const sharedPaths = [...beforeIdentities.keys()].filter(path => afterIdentities.has(path));
      // Only fail closed on an explicit mismatch at a shared identity field.
      // Cursor sometimes changes response envelopes between identical-session reads.
      const stablePath = sharedPaths.find(path => beforeIdentities.get(path) === afterIdentities.get(path));
      if (stablePath === undefined && sharedPaths.length > 0)
        return { status: "account-changed" };
      const principal = stablePath === undefined ? null : beforeIdentities.get(stablePath);
      const plan = data.individualUsage?.plan;
      if (!plan || typeof plan !== "object") return { status: "unsupported-response" };
      const clean = {};
      for (const key of ["enabled", "used", "limit", "autoPercentUsed", "apiPercentUsed", "totalPercentUsed"]) {
        if (typeof plan[key] === "number" && Number.isFinite(plan[key]) || key === "enabled" && typeof plan[key] === "boolean") clean[key] = plan[key];
      }
      const digest = principal === null ? null
        : await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`cursor:${principal}`));
      const identity = digest === null ? null
        : Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
      return { status: "ready", identity, usage: { individualUsage: { plan: clean },
        ...(typeof data.billingCycleEnd === "string" && { billingCycleEnd: data.billingCycleEnd }) } };
    }
    const data = await get("https://cloud.zed.dev/frontend/billing/usage");
    if (!data) return { status: "login-required" };
    const spend = data.current_usage?.token_spend;
    if (!spend || typeof spend.spend_in_cents !== "number") return { status: "unsupported-response" };
    return { status: "ready", identity: null, usage: { current_usage: { token_spend: {
      spend_in_cents: spend.spend_in_cents,
      ...(typeof spend.limit_in_cents === "number" && { limit_in_cents: spend.limit_in_cents }) } } } };
  } catch { return { status: "unavailable" }; }
}
