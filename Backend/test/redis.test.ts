import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { createClient } from 'redis';
import { test } from 'node:test';
import { RedisAllowance } from '../src/rate/redis-allowance.js';
import { ClientCredentials } from '../src/access/credentials.js';
import { buildApplication } from '../src/http/application.js';
import { normalize } from '../src/openrouter/normalize.js';
import { fixtureBytes, headers, token } from './fixtures.js';
test('two API instances share atomic allowances, expiry and Redis outage rejection', async t => {
  if (spawnSync('redis-server', ['--version']).status !== 0) { t.skip('redis-server is required for the integration check'); return; }
  const directory = await mkdtemp('/tmp/thread-rate-');
  const socket = `${directory}/rate.sock`;
  const startStore = () => spawn('redis-server', ['--port', '0', '--unixsocket', socket, '--unixsocketperm', '700', '--save', '', '--appendonly', 'no'], { stdio: 'ignore' });
  let store = startStore();
  t.after(async () => { if (store.exitCode === null && store.signalCode === null) { store.kill(); await once(store, 'exit'); } await rm(directory, { recursive: true, force: true }); });
  const clients = [new RedisAllowance(`unix://${socket}`, () => {}), new RedisAllowance(`unix://${socket}`, () => {})];
  t.after(() => clients.forEach(client => client.close()));
  let connected = false;
  // Readiness is only probed during bounded fixture startup, never by an idle production loop.
  for (let attempt = 0; attempt < 100; attempt++) {
    try { await clients[0]!.connect(); connected = true; break; } catch { await delay(10); }
  }
  assert.ok(connected, 'owned Redis startup failed');
  await clients[1]!.connect();
  const apps = clients.map(allowance => buildApplication({ credentials: new ClientCredentials({ fixture: token }), allowance,
    provider: { async decide(input) { return normalize(fixtureBytes('membership-response'), input); } }, maxInFlight: 8, maxConnections: 64, report: () => {} }));
  t.after(async () => { await Promise.all(apps.map(app => app.close())); });
  const replies = await Promise.all(Array.from({ length: 80 }, (_, i) => apps[i % 2]!.inject({ method: 'POST', url: '/v1/decisions', headers, payload: '{}' })));
  // Queue capacity is deliberately bounded; retry rejected bursts with the same client allowance.
  const accepted = replies.filter(reply => reply.statusCode === 400).length;
  let count = accepted;
  while (count < 60) {
    const reply = await apps[count % 2]!.inject({ method: 'POST', url: '/v1/decisions', headers, payload: '{}' });
    assert.equal(reply.statusCode, 400); count++;
  }
  for (const app of apps) assert.equal((await app.inject({ method: 'POST', url: '/v1/decisions', headers, payload: '{}' })).statusCode, 429);
  const inspector = createClient({ socket: { path: socket, reconnectStrategy: false }, disableOfflineQueue: true });
  inspector.on('error', () => {});
  await inspector.connect();
  t.after(() => { if (inspector.isOpen) inspector.destroy(); });
  const key = `thread:rate:${createHash('sha256').update('fixture').digest('hex')}`;
  const ttl = await inspector.pTTL(key);
  assert.ok(ttl > 0 && ttl <= 60000);
  assert.deepEqual(await inspector.keys('*'), [key]);
  // Shorten only this disposable counter's expiry to verify reset without a minute-long test.
  await inspector.pExpire(key, 20); await delay(40);
  await clients[0]!.consume('fixture');
  assert.equal(await inspector.get(key), '1');
  store.kill(); await once(store, 'exit');
  await assert.rejects(clients[1]!.consume('fixture'), { message: 'rate_store_unavailable' });
  assert.equal((await apps[0]!.inject({ url: '/health/ready' })).statusCode, 503);
  const failed = await apps[1]!.inject({ method: 'POST', url: '/v1/decisions', headers, payload: fixtureBytes('membership') });
  assert.deepEqual(failed.json(), { error: 'rate_store_unavailable' });
  store = startStore();
  let recovered = false;
  for (let attempt = 0; attempt < 150; attempt++) {
    try { await clients[0]!.ready(); await clients[1]!.ready(); recovered = true; break; }
    catch { await delay(10); }
  }
  assert.ok(recovered, 'Redis reconnect did not recover');
  assert.equal((await apps[0]!.inject({ url: '/health/ready' })).statusCode, 204);
  assert.equal((await apps[1]!.inject({ method: 'POST', url: '/v1/decisions', headers, payload: '{}' })).statusCode, 400);
});
