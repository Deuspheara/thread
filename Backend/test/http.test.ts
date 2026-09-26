import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { ClientCredentials } from '../src/access/credentials.js';
import { DecisionFailure } from '../src/contract/failure.js';
import type { DecisionProvider } from '../src/contract/schema.js';
import { buildApplication } from '../src/http/application.js';
import { normalize } from '../src/openrouter/normalize.js';
import { fixtureBytes, headers, token } from './fixtures.js';
function setup(provider?: DecisionProvider, capacity = 8, limit = 1000) {
  let count = 0;
  const logs: string[] = [];
  const app = buildApplication({ credentials: new ClientCredentials({ fixture: token }),
    allowance: { async ready() {}, async consume() { if (++count > limit) throw new DecisionFailure(429, 'rate_limited'); } },
    provider: provider ?? { async decide(input) { return normalize(fixtureBytes(`${input.kind}-response`), input); } },
    maxInFlight: capacity, maxConnections: 64, report: category => logs.push(category) });
  return { app, logs, count: () => count };
}
test('authentication and shared allowance precede validation/provider work', async t => {
  const { app, count } = setup(undefined, 8, 2);
  t.after(() => app.close());
  const post = (payload: string, auth = headers) => app.inject({ method: 'POST', url: '/v1/decisions', headers: auth, payload });
  assert.equal((await post('{}', { ...headers, authorization: 'Bearer ' + 'b'.repeat(43) })).statusCode, 401);
  assert.equal(count(), 0);
  assert.equal((await post('{}')).statusCode, 400);
  const response = await post(fixtureBytes('membership').toString());
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.equal(response.json().confidence, 0.78);
  assert.equal(Object.keys(response.json()).length, 5);
  const limited = await post('{}');
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.headers['retry-after'], '60');
});
test('ingress bounds, exact routes and invalid requests release capacity', async t => {
  const { app } = setup(undefined, 1);
  t.after(() => app.close());
  const post = (payload: string, extra = {}) => app.inject({ method: 'POST', url: '/v1/decisions', headers: { ...headers, ...extra }, payload });
  assert.equal((await post(' '.repeat(65537))).statusCode, 413);
  assert.equal((await post('{}', { 'content-encoding': 'gzip' })).statusCode, 415);
  assert.equal((await post('{}', { 'content-type': 'text/plain' })).statusCode, 415);
  assert.equal((await post('{"a":1,"a":2}')).statusCode, 400);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/decisions?private=value', headers, payload: '{}' })).statusCode, 404);
  assert.equal((await app.inject({ method: 'GET', url: '/v1/decisions' })).statusCode, 405);
  assert.equal((await app.inject({ url: '/unknown' })).statusCode, 404);
  assert.equal((await app.inject({ url: '/health/live' })).statusCode, 204);
  assert.equal((await app.inject({ url: '/health/ready' })).statusCode, 204);
  for (const kind of ['membership', 'transition', 'persistence']) assert.equal((await post(fixtureBytes(kind).toString())).statusCode, 200);
});
test('Redis outage rejects paid requests and readiness, and raw errors never enter logs', async t => {
  let calls = 0;
  const logs: string[] = [];
  const app = buildApplication({ credentials: new ClientCredentials({ fixture: token }),
    allowance: { async ready() { throw new Error('sensitive redis address'); }, async consume() { throw new DecisionFailure(503, 'rate_store_unavailable'); } },
    provider: { async decide() { calls++; throw new Error('secret'); } }, maxInFlight: 1, maxConnections: 2, report: category => logs.push(category) });
  t.after(() => app.close());
  assert.equal((await app.inject({ url: '/health/ready' })).statusCode, 503);
  const reply = await app.inject({ method: 'POST', url: '/v1/decisions', headers, payload: fixtureBytes('membership') });
  assert.equal(reply.statusCode, 503);
  assert.deepEqual(reply.json(), { error: 'rate_store_unavailable' });
  assert.equal(calls, 0);
  assert.deepEqual(logs, ['rate_store_unavailable']);
});
test('capacity survives provider failures and real client disconnects cancel work', async t => {
  const entered = Promise.withResolvers<void>();
  const cancelled = Promise.withResolvers<void>();
  let calls = 0;
  const { app, logs } = setup({ async decide(input, signal) {
    calls++;
    if (calls === 1) { throw new Error('private provider diagnostic'); }
    if (calls === 2) {
      entered.resolve();
      await new Promise<void>(resolve => signal.addEventListener('abort', () => resolve(), { once: true }));
      cancelled.resolve();
      throw new DecisionFailure(504, 'provider_timeout');
    }
    return normalize(fixtureBytes('membership-response'), input);
  } }, 1);
  t.after(() => app.close());
  const post = () => app.inject({ method: 'POST', url: '/v1/decisions', headers, payload: fixtureBytes('membership') });
  assert.deepEqual((await post()).json(), { error: 'internal_error' });
  assert.deepEqual(logs, ['internal_error']);
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address();
  assert.ok(address && typeof address !== 'string');
  const request = httpRequest({ hostname: '127.0.0.1', port: address.port, path: '/v1/decisions', method: 'POST', headers });
  request.on('error', () => {});
  request.end(fixtureBytes('membership'));
  await entered.promise;
  assert.equal((await post()).statusCode, 503);
  request.destroy();
  await cancelled.promise;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal((await post()).statusCode, 200);
  assert.equal(calls, 3);
});
test('a slow body is terminated within its input deadline', async t => {
  const { app } = setup(undefined, 1);
  t.after(() => app.close());
  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address();
  assert.ok(address && typeof address !== 'string');
  const request = httpRequest({ hostname: '127.0.0.1', port: address.port, method: 'POST', path: '/v1/decisions',
    headers: { ...headers, 'content-length': '100' } });
  const response = once(request, 'response');
  request.write('{');
  const [reply] = await response;
  assert.equal(reply.statusCode, 408);
  reply.resume();
  await once(reply, 'end');
  request.destroy();
  assert.equal((await app.inject({ method: 'POST', url: '/v1/decisions', headers, payload: fixtureBytes('membership') })).statusCode, 200);
});
