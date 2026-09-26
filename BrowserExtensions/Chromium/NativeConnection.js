import { TabRestorer } from "./TabRestorer.js";

// Owns one native port and a bounded retry schedule; it stores no tab payloads.
export class NativeConnection {
  constructor(api, browser, onRecovery) {
    this.api = api;
    this.browser = browser;
    this.onRecovery = onRecovery;
    this.port = null;
    this.sequence = 0;
    this.instance = null;
    this.attempts = 0;
    this.retryTimer = null;
    this.needsSnapshot = true;
  }

  connect() {
    if (this.port) return;
    try {
      const port = this.api.runtime.connectNative("app.thread.browser");
      this.port = port;
      this.connection = crypto.randomUUID();
      const restorer = new TabRestorer(this.api, () => this.port === port);
      this.sequence = 0;
      this.needsSnapshot = true;
      port.onMessage.addListener(reply => {
        if (this.port !== port) return;
        if (reply?.kind === "restoreTab") {
          void restorer.restore(reply, this.connection).then(result => {
            if (this.port !== port || result.id === null) return;
            port.postMessage({ version: 1, kind: "restoreResult", connection: this.connection, ...result });
          }).catch(() => { /* A disconnected port cannot receive an acknowledgment. */ });
          return;
        }
        this.api.action.setBadgeText({ text: reply.forwarded ? "" : "!" });
        if (reply.forwarded) {
          if (reply.instance && reply.instance !== this.instance) this.needsSnapshot = true;
          this.instance = reply.instance;
          this.attempts = 0;
          if (this.needsSnapshot) { this.needsSnapshot = false; this.onRecovery(); }
        } else { this.needsSnapshot = true; this.scheduleRetry(); }
      });
      port.onDisconnect.addListener(() => {
        void this.api.runtime.lastError;
        if (this.port !== port) return;
        this.port = null;
        this.needsSnapshot = true;
        this.api.action.setBadgeText({ text: "!" });
        this.scheduleRetry();
      });
      this.post("connected", {});
    } catch {
      this.port = null;
      this.scheduleRetry();
    }
  }

  send(kind, payload = {}) {
    this.connect();
    this.post(kind, payload);
  }

  post(kind, payload) {
    if (!this.port) return;
    try {
      this.port.postMessage({ version: 1, kind, browser: this.browser, connection: this.connection,
        sequence: ++this.sequence, isPrivate: false, ...payload });
    } catch {
      this.port = null;
      this.needsSnapshot = true;
      this.scheduleRetry();
    }
  }

  scheduleRetry() {
    if (this.retryTimer || this.attempts >= 6) return;
    const delay = Math.min(1000 * 2 ** this.attempts++, 32000);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      if (this.port) this.post("connected", {});
      else this.connect();
    }, delay);
  }

  reconnect() {
    this.attempts = 0;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
    this.needsSnapshot = true;
    this.connect();
    this.post("connected", {});
  }
}
