import { TabRestorer } from "../Chromium/TabRestorer.js";

// Serializes Safari's request/reply native messaging with bounded recovery.
export class RequestConnection {
  constructor(api, onRecovery) {
    this.api = api;
    this.onRecovery = onRecovery;
    this.connection = crypto.randomUUID();
    this.sequence = 0;
    this.pending = [];
    this.draining = false;
    this.instance = null;
    this.needsSnapshot = true;
    this.attempts = 0;
    this.retryTimer = null;
    this.control = null;
  }

  connect() { this.connectControl(); this.send("connected"); }

  connectControl() {
    if (this.control || typeof this.api.runtime.connectNative !== "function") return;
    try {
      const port = this.api.runtime.connectNative("app.thread.desktop");
      this.control = port;
      const restorer = new TabRestorer(this.api, () => this.control === port);
      port.onMessage.addListener(message => {
        if (message?.name && message.name !== "restoreTab") return;
        const command = message?.name === "restoreTab" ? (message.userInfo ?? message.message) : message;
        if (command?.kind !== "restoreTab") return;
        void restorer.restore(command, this.connection).then(result => {
          if (this.control !== port || result.id === null) return;
          return this.api.runtime.sendNativeMessage("app.thread.desktop", {
            version: 1, kind: "restoreResult", connection: this.connection, ...result
          });
        }).catch(() => { /* A disconnected native channel cannot receive the result. */ });
      });
      port.onDisconnect.addListener(() => {
        if (this.control !== port) return;
        this.control = null;
        this.needsSnapshot = true;
        this.scheduleRetry();
      });
    } catch { this.control = null; }
  }

  send(kind, payload = {}) {
    if (this.pending.length >= 256) {
      this.pending.shift();
      this.needsSnapshot = true;
    }
    this.pending.push({ kind, payload });
    void this.drain();
  }

  async drain() {
    if (this.draining) return;
    this.draining = true;
    try {
      while (this.pending.length) {
        const { kind, payload } = this.pending.shift();
        const sequence = ++this.sequence;
        try {
          const reply = await this.api.runtime.sendNativeMessage("app.thread.desktop", {
            ...payload, version: 1, kind, browser: "safari", connection: this.connection,
            sequence, isPrivate: false
          });
          if (reply?.sequence !== sequence || !reply.forwarded || typeof reply.instance !== "string") {
            this.failed();
            break;
          }
          this.api.action.setBadgeText({ text: "" });
          if (reply.instance !== this.instance) this.needsSnapshot = true;
          this.instance = reply.instance;
          this.attempts = 0;
          if (this.retryTimer) clearTimeout(this.retryTimer);
          this.retryTimer = null;
          if (this.needsSnapshot) {
            this.needsSnapshot = false;
            this.onRecovery();
          }
        } catch {
          this.failed();
          break;
        }
      }
    } finally { this.draining = false; }
  }

  failed() {
    this.pending = [];
    this.needsSnapshot = true;
    this.api.action.setBadgeText({ text: "!" });
    if (this.retryTimer || this.attempts >= 6) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      this.connect();
    }, 1000 * 2 ** this.attempts++);
  }

  reconnect() {
    this.attempts = 0;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
    this.needsSnapshot = true;
    this.connect();
  }
}
