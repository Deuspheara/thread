import assert from 'node:assert/strict';
import { createServer, type RequestListener } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { OpenRouterDecisions } from '../src/openrouter/client.js';
import { buildQuestion } from '../src/openrouter/question.js';
import { normalize } from '../src/openrouter/normalize.js';
import { fixture, fixtureBytes } from './fixtures.js';
export async function upstream(handler: RequestListener) {
  const server = createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  return { url: `http://127.0.0.1:${address.port}`, close: async () => {
    server.closeAllConnections(); server.close(); await once(server, 'close');
  } };
}
test('provider translation retains selected probabilities and excludes correlation IDs', () => {
  for (const kind of ['membership', 'transition', 'persistence']) {
    const input = fixture(kind);
    const payload = JSON.stringify(buildQuestion(input));
    assert.ok(!payload.includes(input.requestID));
    assert.ok(payload.includes('untrusted metadata'));
    const response = normalize(fixtureBytes(`${kind}-response`), input);
    assert.equal(response.confidence, kind === 'transition' ? 0.96 : 0.78);
    assert.equal(response.requestID, input.requestID);
    assert.equal(Object.keys(response).length, 5);
  }
  const response = normalize(Buffer.from(fixtureBytes('transition-response').toString().replace('0.96', '0.03')), fixture('transition'));
  assert.equal(response.confidence, 0.97);
  assert.ok(response.kind === 'transition' && !response.shouldTransition);
});
test('malformed provider responses fail closed', () => {
  const original = fixtureBytes('membership-response').toString();
  for (const [from, to] of [
    ['"choice":"c0"', '"choice":"c7"'], ['"c0":0.78', '"c0":-1'], ['"c0":0.78', '"c0":0.1'],
    ['"confidence":0.67', '"confidence":5'], ['"type":"choice"', '"type":"score"'],
    ['typesafe/jev-1.13-20260917', 'unexpected-model'], ['"answers":{', '"error":{"message":"sensitive"},"answers":{'],
    ['"undetermined":0', '"undetermined":null']
  ]) {
    assert.ok(from !== undefined && to !== undefined);
    assert.throws(() => normalize(Buffer.from(original.replace(from, to)), fixture()), { message: 'invalid_provider_response' });
  }
});
test('pooled transport bounds responses, refuses redirects and cancels upstream', async t => {
  let calls = 0;
  const good = await upstream(async (request, response) => {
    calls++;
    assert.equal(request.headers.authorization, 'Bearer fixture-key');
    const chunks: Buffer[] = [];
    for await (const chunk of request) chunks.push(chunk as Buffer);
    assert.ok(!Buffer.concat(chunks).toString().includes(fixture().requestID));
    response.setHeader('Content-Type', 'application/json');
    response.end(fixtureBytes('membership-response'));
  });
  t.after(good.close);
  const client = new OpenRouterDecisions('fixture-key', good.url);
  t.after(() => client.close());
  assert.equal((await client.decide(fixture(), new AbortController().signal)).confidence, 0.78);
  for (const [status, body, category] of [
    [200, 'x'.repeat(65537), 'provider_response_too_large'],
    [200, '{"error":{"message":"secret"}}', 'invalid_provider_response'],
    [307, '', 'provider_unavailable'], [429, 'secret', 'provider_unavailable'], [503, 'secret', 'provider_unavailable']
  ] as const) {
    const server = await upstream((_request, response) => {
      response.writeHead(status, { 'content-type': 'application/json', location: good.url }); response.end(body);
    });
    const transport = new OpenRouterDecisions('fixture-key', server.url);
    try { await assert.rejects(transport.decide(fixture(), new AbortController().signal), { message: category }); }
    finally { await transport.close(); await server.close(); }
  }
  assert.equal(calls, 1);
  const received = Promise.withResolvers<void>();
  const slow = await upstream((request, response) => {
    request.resume();
    response.once('close', () => received.resolve());
  });
  const timeout = new OpenRouterDecisions('fixture-key', slow.url, 30);
  try {
    await assert.rejects(timeout.decide(fixture(), new AbortController().signal), { message: 'provider_timeout' });
    await received.promise;
  } finally { await timeout.close(); await slow.close(); }
});
