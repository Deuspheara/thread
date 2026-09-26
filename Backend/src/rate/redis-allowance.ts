import { createHash } from 'node:crypto';
import { createClient } from 'redis';
import { DecisionFailure, fail } from '../contract/failure.js';
import type { ClientAllowance } from '../contract/schema.js';
const consume = `local count = redis.call('INCR', KEYS[1])
if count == 1 then redis.call('PEXPIRE', KEYS[1], 60000) end
return count`;
/** Owns a bounded Redis connection and atomic expiring per-client allowances. */
export class RedisAllowance implements ClientAllowance {
  private readonly client;
  constructor(url: string, private readonly report: (category: string) => void, private readonly limit = 60) {
    try {
      const parsed = new URL(url);
      if (!['redis:', 'rediss:', 'unix:'].includes(parsed.protocol) || !Number.isInteger(limit) || limit < 1 || limit > 600) fail(500, 'invalid_configuration');
      const socket = { connectTimeout: 1000, reconnectStrategy: (retries: number) => Math.min(100 * 2 ** Math.min(retries, 4), 1000) };
      this.client = createClient({
        ...(parsed.protocol === 'unix:' ? { socket: { ...socket, path: parsed.pathname } } : { url, socket }),
        disableOfflineQueue: true, commandsQueueMaxLength: 8, commandOptions: { timeout: 500 }
      });
      this.client.on('error', () => report('rate_store_diagnostic'));
    } catch { fail(500, 'invalid_configuration'); }
  }
  async connect(): Promise<void> {
    const timeout = setTimeout(() => { if (this.client.isOpen) this.client.destroy(); }, 1000).unref();
    try { await this.client.connect(); await this.ready(); }
    catch { fail(503, 'rate_store_unavailable'); }
    finally { clearTimeout(timeout); }
  }
  async ready(): Promise<void> {
    try { await this.client.withCommandOptions({ timeout: 250 }).ping(); }
    catch { fail(503, 'rate_store_unavailable'); }
  }
  async consume(clientID: string): Promise<void> {
    const key = `thread:rate:${createHash('sha256').update(clientID).digest('hex')}`;
    try {
      const count = await this.client.eval(consume, { keys: [key], arguments: [] });
      if (typeof count !== 'number') fail(503, 'rate_store_unavailable');
      if (count > this.limit) fail(429, 'rate_limited');
    } catch (error) {
      if (error instanceof DecisionFailure) throw error;
      fail(503, 'rate_store_unavailable');
    }
  }
  close(): void {
    if (this.client.isOpen) this.client.destroy();
    this.report('rate_store_closed');
  }
}
