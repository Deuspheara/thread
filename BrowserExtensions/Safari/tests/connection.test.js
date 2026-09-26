import test from "node:test";
import assert from "node:assert/strict";
import { RequestConnection } from "../RequestConnection.js";

const settle = () => new Promise(resolve => setImmediate(resolve));

test("Safari serializes native requests and refreshes inventory after app restart", async () => {
  const messages = [];
  let instance = "first";
  let snapshots = 0;
  const api = { runtime: { async sendNativeMessage(app, message) {
    assert.equal(app, "app.thread.desktop");
    messages.push(message);
    return { sequence: message.sequence, forwarded: true, instance };
  } }, action: { setBadgeText() {} } };
  const connection = new RequestConnection(api, () => snapshots++);
  connection.connect();
  connection.send("focusCleared");
  await settle();
  instance = "restarted";
  connection.send("focusCleared");
  await settle();
  assert.equal(snapshots, 2);
  assert.deepEqual(messages.map(message => message.sequence), [1, 2, 3]);
  assert.ok(messages.every(message => message.browser === "safari" && !message.isPrivate));
});

test("Safari bounds pending requests and rejects mismatched acknowledgments", async () => {
  let release;
  let snapshots = 0;
  const badges = [];
  const api = { runtime: { sendNativeMessage: () => new Promise(resolve => { release = resolve; }) },
    action: { setBadgeText: value => badges.push(value.text) } };
  const connection = new RequestConnection(api, () => snapshots++);
  connection.attempts = 6; // Exhausted retries; next browser activity can still recover.
  connection.connect();
  for (let i = 0; i < 1000; i++) connection.send("focusCleared");
  assert.equal(connection.pending.length, 256);
  release({ sequence: 999, forwarded: true, instance: "wrong" });
  await settle();
  assert.equal(snapshots, 0);
  assert.equal(connection.pending.length, 0);
  assert.equal(connection.needsSnapshot, true);
  assert.equal(badges.at(-1), "!");
  assert.equal(connection.retryTimer, null);
});
