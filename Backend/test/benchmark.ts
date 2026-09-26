import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { performance } from 'node:perf_hooks';
import { setTimeout as delay } from 'node:timers/promises';
import { request } from 'undici';
import { ClientCredentials } from '../src/access/credentials.js';
import { buildApplication } from '../src/http/application.js';
import { OpenRouterDecisions } from '../src/openrouter/client.js';
import { fixtureBytes, headers, token } from './fixtures.js';

// Disposable loopback benchmark: fictional metadata, mocked upstream, no paid calls.
let active = 0;
let peak = 0;
const upstream = createServer(async (input, output) => {
  input.resume();
  active++;
  peak = Math.max(peak, active);
  await delay(25);
  active--;
  output.setHeader('Content-Type', 'application/json');
  output.end(fixtureBytes('membership-response'));
});
upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
const address = upstream.address(); assert.ok(address && typeof address !== 'string');
const provider = new OpenRouterDecisions('fictional-key', `http://127.0.0.1:${address.port}`);
const app = buildApplication({ credentials: new ClientCredentials({ fixture: token }), provider,
  allowance: { async consume() {}, async ready() {} }, maxInFlight: 8, maxConnections: 64, report: () => {} });
try {
  const url = await app.listen({ host: '127.0.0.1', port: 0 });
  const latencies: number[] = [];
  const call = async () => {
    const started = performance.now();
    const response = await request(url + '/v1/decisions', { method: 'POST', headers, body: fixtureBytes('membership') });
    await response.body.dump();
    latencies.push(performance.now() - started);
    return response.statusCode;
  };
  // Warm schema/transport paths before timing.
  await call(); latencies.length = 0;
  const started = performance.now();
  for (let batch = 0; batch < 20; batch++) assert.ok((await Promise.all(Array.from({ length: 8 }, call))).every(code => code === 200));
  const elapsed = performance.now() - started;
  const burst = await Promise.all(Array.from({ length: 32 }, call));
  assert.equal(peak, 8);
  assert.ok(burst.includes(503));
  assert.equal(await call(), 200);
  const timed = latencies.slice(0, 160).sort((a, b) => a - b);
  process.stdout.write(JSON.stringify({ node: process.version, requests: 160, concurrency: 8, upstreamDelayMs: 25,
    elapsedMs: Math.round(elapsed), requestsPerSecond: Math.round(160000 / elapsed),
    p50Ms: Math.round(timed[80]!), p95Ms: Math.round(timed[152]!), maxProviderInFlight: peak,
    burstAccepted: burst.filter(code => code === 200).length, burstRejected: burst.filter(code => code === 503).length,
    rssMiB: Math.round(process.memoryUsage().rss / 1048576) }) + '\n');
} finally {
  await app.close(); await provider.close();
  upstream.closeAllConnections(); upstream.close(); await once(upstream, 'close');
}
