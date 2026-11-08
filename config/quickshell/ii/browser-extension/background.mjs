import { readUsage } from "./usage.mjs";

const HOST = "org.illogical_impulse.ai_quotas";
const URLS = { cursor: "https://cursor.com/dashboard", zed: "https://dashboard.zed.dev/account" };
const MATCHES = { cursor: ["https://cursor.com/*"], zed: ["https://dashboard.zed.dev/*", "https://zed.dev/*"] };
let running = false;

export async function sync() {
  if (running) return;
  running = true;
  let retry = false;
  try {
    const state = await chrome.runtime.sendNativeMessage(HOST, { action: "state" });
    retry = (state.requests ?? []).some(task => task.login === true);
    for (const task of (state.requests ?? []).slice(0, 2)) {
      if (!Object.hasOwn(URLS, task.provider) || !/^[a-f0-9]{64}$/.test(task.nonce)) continue;
      const tabs = await chrome.tabs.query({ url: MATCHES[task.provider] });
      let tab = tabs.find(candidate => candidate.status === "complete") ?? tabs[0];
      if (!tab) {
        // Background refresh never opens provider pages. Only an explicit login
        // requested from the panel may create a tab.
        if (task.login !== true) continue;
        await chrome.tabs.create({ url: URLS[task.provider], active: true });
        continue; // Read when its load event arrives; never inject into a login page.
      }
      if (tab.status !== "complete") continue;
      const [result] = await chrome.scripting.executeScript({ target: { tabId: tab.id },
        func: readUsage, args: [task.provider] });
      const data = result?.result;
      if (data?.status !== "ready") {
        const code = ["login-required", "unsupported-response", "account-changed"].includes(data?.status) ? data.status : "unavailable";
        await chrome.runtime.sendNativeMessage(HOST, { action: "report", provider: task.provider, nonce: task.nonce, code });
        await chrome.action.setBadgeText({ text: "!" });
        continue;
      }
      const answer = await chrome.runtime.sendNativeMessage(HOST, {
        action: "publish", provider: task.provider, nonce: task.nonce, usage: data.usage, identity: data.identity });
      await chrome.action.setBadgeText({ text: answer.ok ? "✓" : "!" });
      if (!answer.ok) await chrome.runtime.sendNativeMessage(HOST, { action: "report", provider: task.provider,
        nonce: task.nonce, code: answer.code === "unsupported-response" ? answer.code : "unavailable" });
    }
  } catch { await chrome.action.setBadgeText({ text: "!" }).catch(() => {}); }
  finally {
    running = false;
    if (retry) setTimeout(() => { void sync(); }, 2000);
  }
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("quota-refresh", { periodInMinutes: 0.5 });
  void sync();
});
chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create("quota-refresh", { periodInMinutes: 0.5 });
  void sync();
});
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "quota-refresh") void sync(); });
chrome.tabs.onUpdated.addListener((_id, change, tab) => {
  if (change.status === "complete" && /^https:\/\/(?:cursor\.com|zed\.dev|dashboard\.zed\.dev)\//.test(tab.url ?? "")) void sync();
});
chrome.action.onClicked.addListener(() => { void sync(); });
