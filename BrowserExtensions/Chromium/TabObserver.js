import { sanitizedTab } from "./privacy.js";

// Collects only current normal tabs, coalescing event bursts into a bounded work queue.
export class TabObserver {
  constructor(api, transport) {
    this.api = api;
    this.transport = transport;
    this.known = new Set();
    this.pending = new Map();
    this.draining = false;
    this.repairNeeded = false;
  }

  start() {
    this.api.tabs.onCreated.addListener(tab => this.enqueue(`tab:${tab.id}`, () => this.observe(tab.id, "opened")));
    this.api.tabs.onUpdated.addListener(id => this.enqueue(`tab:${id}`, () => this.observe(id, "updated")));
    this.api.tabs.onActivated.addListener(({ tabId }) => this.enqueue(`tab:${tabId}`, () => this.observe(tabId, "activated")));
    this.api.tabs.onRemoved.addListener(id => this.enqueue(`tab:${id}`, async () => this.close(id)));
    this.api.tabs.onAttached.addListener(id => this.enqueue(`tab:${id}`, () => this.observe(id, "updated")));
    this.api.windows.onFocusChanged.addListener(() => this.enqueue("focus", () => this.focus()));
  }

  enqueue(key, work) {
    this.pending.set(key, work);
    if (this.pending.size > 256) {
      this.pending.delete(this.pending.keys().next().value);
      this.repairNeeded = true;
    }
    void this.drain();
  }

  async drain() {
    if (this.draining) return;
    this.draining = true;
    try {
      while (this.pending.size) {
        const [key, work] = this.pending.entries().next().value;
        this.pending.delete(key);
        try { await work(); } catch { /* Tab/window disappeared between event and read. */ }
      }
      if (this.repairNeeded) { this.repairNeeded = false; await this.snapshot(); }
    } finally {
      this.draining = false;
      if (this.pending.size) void this.drain();
    }
  }

  async observe(id, kind) {
    let tab;
    try { tab = await this.api.tabs.get(id); } catch { this.close(id); return; }
    const safe = sanitizedTab(tab);
    if (!safe) {
      this.close(id);
      if (tab.active && (await this.api.windows.get(tab.windowId)).focused) this.transport.send("focusCleared");
      return;
    }
    if (tab.status === "loading") safe.title = "";
    const window = await this.api.windows.get(tab.windowId);
    if (window.incognito !== false) { this.close(id); return; }
    if (!this.known.has(id)) this.transport.send("opened", safe);
    this.known.delete(id);
    this.known.add(id);
    if (this.known.size > 2048) this.known.delete(this.known.values().next().value);
    if (safe.active && window.focused) this.transport.send("activated", safe);
    else if (kind !== "opened") this.transport.send("updated", safe);
  }

  close(id) {
    // Unknown/private tabs never transmit even their numeric identifiers.
    if (this.known.delete(id)) this.transport.send("closed", { tabID: id });
  }

  async focus() {
    const window = await this.api.windows.getLastFocused();
    // Switching to an editor preserves the last public resource as recent evidence.
    if (!window.focused) return;
    if (window.incognito !== false) { this.transport.send("focusCleared"); return; }
    const tabs = await this.api.tabs.query({ windowId: window.id, active: true });
    if (tabs.length) await this.observe(tabs[0].id, "activated");
    else this.transport.send("focusCleared");
  }

  resynchronize() {
    this.known.clear();
    this.enqueue("snapshot", () => this.snapshot());
  }

  async snapshot() {
    const tabs = await this.api.tabs.query({});
    const existing = new Set(tabs.filter(tab => sanitizedTab(tab)).map(tab => tab.id));
    for (const id of this.known) if (!existing.has(id)) this.close(id);
    // Bound initial inventory; focused tab is handled afterward even beyond this cap.
    for (const tab of tabs.filter(tab => !tab.incognito).slice(0, 2048)) await this.observe(tab.id, "opened");
    await this.focus();
  }
}
