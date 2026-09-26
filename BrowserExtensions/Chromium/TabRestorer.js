import { sanitizedTab } from "./privacy.js";

// Executes bounded, idempotent native restore requests without touching private tabs.
export class TabRestorer {
  constructor(api, isCurrent = () => true) {
    this.api = api;
    this.isCurrent = isCurrent;
    this.requests = new Map();
    this.pending = 0;
    this.tail = Promise.resolve();
  }

  restore(command, connection) {
    const safe = this.validate(command, connection);
    if (!safe) return Promise.resolve({ id: null, outcome: "refused" });
    const fingerprint = JSON.stringify(safe);
    const previous = this.requests.get(safe.id);
    if (previous) return previous.fingerprint === fingerprint ? previous.result : Promise.resolve({ id: safe.id, outcome: "refused" });
    if (this.pending >= 16) return Promise.resolve({ id: safe.id, outcome: "busy" });
    this.pending++;
    const result = this.tail.then(async () => {
      try { return { id: safe.id, outcome: await this.execute(safe) }; }
      catch { return { id: safe.id, outcome: "failed" }; }
      finally { this.pending--; }
    });
    this.tail = result.then(() => {});
    this.requests.set(safe.id, { fingerprint, result });
    if (this.requests.size > 128) this.requests.delete(this.requests.keys().next().value);
    return result;
  }

  validate(command, connection) {
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!command || command.version !== 1 || command.kind !== "restoreTab" || !uuid.test(command.id) ||
        !Number.isFinite(command.expiresAt) || command.expiresAt <= Date.now() || command.expiresAt > Date.now() + 10000 ||
        !uuid.test(connection) || command.connection !== connection || typeof command.url !== "string" ||
        new TextEncoder().encode(command.url).length > 4096 || /[\u0000-\u0020]/.test(command.url) ||
        (command.tabID !== undefined && (!Number.isSafeInteger(command.tabID) || command.tabID < 0))) return null;
    let url;
    try { url = new URL(command.url); } catch { return null; }
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password ||
        url.search || url.hash || command.url.includes("?") || command.url.includes("#")) return null;
    return { id: command.id, connection, url: url.href, tabID: command.tabID, expiresAt: command.expiresAt };
  }

  current(command) { return this.isCurrent() && Date.now() < command.expiresAt; }

  async execute(command) {
    if (!this.current(command)) return "refused";
    if (command.tabID !== undefined) {
      let tab;
      try { tab = await this.api.tabs.get(command.tabID); } catch { /* Closed or disconnected tab; look for its URL. */ }
      if (tab && await this.activate(tab, command)) return "focused";
    }
    const tabs = await this.api.tabs.query({});
    for (const tab of tabs.slice(0, 2048)) {
      if (await this.activate(tab, command)) return "focused";
    }
    const windows = await this.api.windows.getAll({ windowTypes: ["normal"] });
    const target = windows.find(window => window.incognito === false && window.type === "normal" && Number.isSafeInteger(window.id));
    if (target) {
      // Recheck immediately before mutation; never use the browser's implicit current window.
      const current = await this.api.windows.get(target.id);
      if (current.incognito !== false || current.type !== "normal" || !this.current(command)) return "failed";
      await this.api.tabs.create({ windowId: target.id, url: command.url, active: true });
      await this.api.windows.update(target.id, { focused: true });
    } else {
      if (!this.current(command)) return "refused";
      await this.api.windows.create({ url: command.url, incognito: false, focused: true, type: "normal" });
    }
    return "reopened";
  }

  async activate(candidate, command) {
    const url = command.url;
    const safe = sanitizedTab(candidate);
    if (!safe || safe.url !== url) return false;
    let tab, window;
    try {
      tab = await this.api.tabs.get(candidate.id);
      window = await this.api.windows.get(tab.windowId);
    } catch { return false; }
    if (sanitizedTab(tab)?.url !== url || window.incognito !== false || !this.current(command)) return false;
    await this.api.tabs.update(tab.id, { active: true });
    await this.api.windows.update(tab.windowId, { focused: true });
    return true;
  }
}
