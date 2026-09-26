import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ClientCredentials } from '../src/access/credentials.js';
import { readConfiguration } from '../src/config.js';
import { token } from './fixtures.js';
test('independent tokens authenticate and invalid provisioning fails', () => {
  const credentials = new ClientCredentials({ fixture: token });
  assert.equal(credentials.authenticate(`Bearer ${token}`), 'fixture');
  for (const header of [undefined, token, `Bearer ${'b'.repeat(43)}`, `bearer ${token}`, `Bearer ${token} `]) assert.throws(() => credentials.authenticate(header));
  for (const tokens of [{}, [], null, { a: 'short' }, { a: 'sk-or-' + token }, { a: token, b: token }, { 'bad/id': token }, Object.fromEntries(Array.from({ length: 1025 }, (_, i) => [`a${i}`, token + i]))]) assert.throws(() => new ClientCredentials(tokens));
});
test('startup settings reject invalid numbers, models and secrets without diagnostics', () => {
  const environment = { OPENROUTER_API_KEY: 'sk-or-' + 'a'.repeat(32), THREAD_CLIENT_TOKENS: JSON.stringify({ fixture: token }), THREAD_REDIS_URL: 'redis://127.0.0.1:6379/0' };
  assert.equal(readConfiguration(environment).port, 8787);
  for (const change of [{ THREAD_API_PORT: 'NaN' }, { THREAD_MAX_IN_FLIGHT: '0' }, { THREAD_API_HOST: 'public.example' }, { OPENROUTER_MODEL: 'other' }, { OPENROUTER_API_KEY: 'private diagnostic' }, { THREAD_REDIS_URL: '' }, { THREAD_CLIENT_TOKENS: '{' }]) {
    assert.throws(() => readConfiguration({ ...environment, ...change }), { message: 'invalid_configuration' });
  }
});
