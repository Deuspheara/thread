import { createHash, timingSafeEqual } from 'node:crypto';
import { fail } from '../contract/failure.js';
const tokenPattern = /^[A-Za-z0-9_-]{32,128}$/;
const hash = (value: string) => createHash('sha256').update(value).digest();
/** Authenticates provisioned independent Thread credentials using constant-time digest comparisons. */
export class ClientCredentials {
  private readonly clients: ReadonlyArray<{ id: string; digest: Buffer }>;
  constructor(tokens: unknown) {
    if (!tokens || typeof tokens !== 'object' || Array.isArray(tokens)) fail(500, 'invalid_configuration');
    const entries = Object.entries(tokens);
    const seen = new Set<string>();
    if (entries.length < 1 || entries.length > 1024) fail(500, 'invalid_configuration');
    this.clients = entries.map(([id, token]) => {
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(id) || typeof token !== 'string' || !tokenPattern.test(token) || token.startsWith('sk-or-') || seen.has(token)) fail(500, 'invalid_configuration');
      seen.add(token);
      return { id, digest: hash(token) };
    });
  }
  authenticate(header: string | undefined): string {
    if (!header?.startsWith('Bearer ') || !tokenPattern.test(header.slice(7))) fail(401, 'authentication_required');
    const digest = hash(header.slice(7));
    let id: string | undefined;
    for (const client of this.clients) if (timingSafeEqual(digest, client.digest)) id = client.id;
    if (id === undefined) fail(401, 'authentication_required');
    return id;
  }
}
