import { fail } from './contract/failure.js';
import { strictJSON } from './contract/json.js';
/** Validated immutable process configuration; secrets are never logged. */
export function readConfiguration(environment: NodeJS.ProcessEnv) {
  const invalid = () => fail(500, 'invalid_configuration');
  const number = (name: string, fallback: number, min: number, max: number) => {
    const raw = environment[name];
    const value = raw === undefined || raw === '' ? fallback : Number(raw);
    if ((raw && !/^\d+$/.test(raw)) || !Number.isInteger(value) || value < min || value > max) invalid();
    return value;
  };
  const key = environment.OPENROUTER_API_KEY ?? '';
  if (!/^sk-or-[A-Za-z0-9_-]{16,256}$/.test(key)) invalid();
  if (environment.OPENROUTER_MODEL && environment.OPENROUTER_MODEL !== 'typesafe/jev-1.13') invalid();
  const host = environment.THREAD_API_HOST || '127.0.0.1';
  if (!['127.0.0.1', '0.0.0.0'].includes(host)) invalid();
  const redisURL = environment.THREAD_REDIS_URL;
  if (!redisURL) return invalid();
  let tokens: unknown;
  try { tokens = strictJSON(Buffer.from(environment.THREAD_CLIENT_TOKENS ?? '')); } catch { return invalid(); }
  return { key, tokens, host, redisURL, port: number('THREAD_API_PORT', 8787, 1, 65535),
    maxInFlight: number('THREAD_MAX_IN_FLIGHT', 8, 1, 128), maxConnections: number('THREAD_MAX_CONNECTIONS', 64, 1, 4096) };
}
