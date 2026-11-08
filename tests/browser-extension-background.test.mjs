import { test } from "node:test";
import assert from "node:assert/strict";

const noop = { addListener() {} };
let sequence = 0;

function installChrome({ tabs = [], requests = [], status = "ready" } = {}) {
  const state = { tabs: [...tabs], created: [], scripts: [], published: [], stateCalls: 0, nextId: 1 };
  globalThis.chrome = {
    runtime: {
      onInstalled: noop,
      onStartup: noop,
      sendNativeMessage: async (_host, message) => {
        if (message.action === "state") {
          const task = requests[state.stateCalls++];
          return { requests: task ? [task] : [] };
        }
        if (message.action === "publish") {
          state.published.push(message);
          return { ok: true };
        }
        return { ok: true };
      },
    },
    tabs: {
      onUpdated: noop,
      query: async ({ url }) => state.tabs.filter(tab => url.some(pattern => tab.url.startsWith(pattern.slice(0, -1)))),
      create: async options => {
        state.created.push(options);
        const tab = { id: state.nextId++, ...options, status: "complete", windowId: 1 };
        state.tabs.push(tab);
        return tab;
      },
      get: async id => state.tabs.find(tab => tab.id === id),
      remove: async id => {
        const index = state.tabs.findIndex(tab => tab.id === id);
        if (index >= 0) state.tabs.splice(index, 1);
      },
    },
    scripting: {
      executeScript: async ({ target, args }) => {
        state.scripts.push({ tabId: target.tabId, provider: args[0] });
        return [{ result: { status, usage: { individualUsage: { plan: { totalPercentUsed: 5 } } },
          identity: "c".repeat(64) } }];
      },
    },
    action: { setBadgeText: async () => {}, onClicked: noop },
    alarms: { create() {}, onAlarm: noop },
  };
  return state;
}

async function loadSync() {
  const { sync } = await import(`../config/quickshell/ii/browser-extension/background.mjs?test=${++sequence}`);
  return sync;
}

test("background refresh never opens provider pages", async () => {
  const state = installChrome({
    requests: [
      { provider: "cursor", nonce: "a".repeat(64), login: false },
      { provider: "zed", nonce: "b".repeat(64), login: false },
    ],
  });
  try {
    const sync = await loadSync();
    await sync();
  } finally {
    delete globalThis.chrome;
  }

  assert.deepEqual(state.created, []);
  assert.deepEqual(state.scripts, []);
});

test("background refresh reads an already-open provider tab", async () => {
  const state = installChrome({
    tabs: [{ id: 7, url: "https://cursor.com/dashboard", status: "complete", windowId: 1 }],
    requests: [{ provider: "cursor", nonce: "a".repeat(64), login: false }],
  });
  try {
    const sync = await loadSync();
    await sync();
  } finally {
    delete globalThis.chrome;
  }

  assert.deepEqual(state.created, []);
  assert.deepEqual(state.scripts, [{ tabId: 7, provider: "cursor" }]);
  assert.equal(state.published.length, 1);
  assert.equal(state.published[0].provider, "cursor");
});

test("explicit login may open one active provider tab", async () => {
  const state = installChrome({
    requests: [{ provider: "zed", nonce: "b".repeat(64), login: true }],
  });
  try {
    const sync = await loadSync();
    await sync();
    // login requests schedule one 2 s retry; let it drain before removing the mock.
    await new Promise(resolve => setTimeout(resolve, 2100));
  } finally {
    delete globalThis.chrome;
  }

  assert.deepEqual(state.created, [{ url: "https://dashboard.zed.dev/account", active: true }]);
  assert.deepEqual(state.scripts, []);
});
