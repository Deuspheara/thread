import { Pool } from 'undici';
import { DecisionFailure, fail } from '../contract/failure.js';
import type { DecisionProvider, DecisionRequest, DecisionResponse } from '../contract/schema.js';
import { buildQuestion } from './question.js';
import { normalize } from './normalize.js';
/** Owns bounded, cancellable, pooled OpenRouter transport without redirects or proxy inheritance. */
export class OpenRouterDecisions implements DecisionProvider {
  private readonly pool: Pool;
  private readonly path: string;
  constructor(private readonly key: string, endpoint = 'https://openrouter.ai/api/alpha/decisions', private readonly timeout = 3000) {
    const url = new URL(endpoint);
    this.path = url.pathname + url.search;
    this.pool = new Pool(url.origin, { connections: 64, pipelining: 1, headersTimeout: timeout, bodyTimeout: timeout, maxResponseSize: 65536 });
  }
  async decide(input: DecisionRequest, cancellation: AbortSignal): Promise<DecisionResponse> {
    const signal = AbortSignal.any([cancellation, AbortSignal.timeout(this.timeout)]);
    try {
      const response = await this.pool.request({ path: this.path, method: 'POST', signal,
        headers: { authorization: `Bearer ${this.key}`, 'content-type': 'application/json', accept: 'application/json', 'accept-encoding': 'identity' },
        body: JSON.stringify(buildQuestion(input))
      });
      // Stream errors still reject iteration; intentional early destruction also emits an error.
      // The enclosing catch maps transport failures, so never emit raw stream diagnostics.
      response.body.on('error', () => {});
      try {
        if (response.statusCode !== 200) fail(response.statusCode === 429 ? 429 : 503, 'provider_unavailable');
        const contentType = response.headers['content-type'];
        if (typeof contentType !== 'string' || contentType.split(';')[0]?.trim().toLowerCase() !== 'application/json') fail(502, 'invalid_provider_response');
        const encoding = response.headers['content-encoding'];
        if (encoding && encoding !== 'identity') fail(502, 'invalid_provider_response');
        const chunks: Buffer[] = [];
        let length = 0;
        for await (const chunk of response.body) {
          const buffer = Buffer.from(chunk as Uint8Array);
          length += buffer.length;
          if (length > 65536) fail(502, 'provider_response_too_large');
          chunks.push(buffer);
        }
        return normalize(Buffer.concat(chunks), input);
      } finally { response.body.destroy(); }
    } catch (error) {
      if (error instanceof DecisionFailure) throw error;
      if (signal.aborted) fail(504, 'provider_timeout');
      if (error && typeof error === 'object' && 'code' in error && error.code === 'UND_ERR_RES_EXCEEDED_MAX_SIZE') fail(502, 'provider_response_too_large');
      fail(503, 'provider_unavailable');
    }
  }
  async close(): Promise<void> { await this.pool.destroy(); }
}
