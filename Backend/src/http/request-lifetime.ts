import type { FastifyReply, FastifyRequest } from 'fastify';
import { fail } from '../contract/failure.js';
/** Owns one request's deadlines, cancellation listeners and idempotent capacity release. */
export class RequestLifetime {
  readonly controller = new AbortController();
  private working = false;
  private released = false;
  private readonly inputTimer: NodeJS.Timeout;
  private readonly responseTimer: NodeJS.Timeout;
  constructor(private readonly request: FastifyRequest, private readonly reply: FastifyReply, private readonly release: () => void) {
    request.raw.once('aborted', this.disconnect);
    reply.raw.once('close', this.disconnect);
    this.inputTimer = setTimeout(() => {
      this.controller.abort();
      if (!reply.sent) void reply.code(408).send({ error: 'request_timeout' });
    }, 3000).unref();
    this.responseTimer = setTimeout(() => {
      this.controller.abort();
      reply.raw.destroy();
    }, 7000).unref();
  }
  begin(): AbortSignal {
    clearTimeout(this.inputTimer);
    if (this.controller.signal.aborted) fail(408, 'request_timeout');
    this.working = true;
    return this.controller.signal;
  }
  complete(): void {
    this.working = false;
    this.releaseCapacity();
    if (this.reply.raw.destroyed) this.dispose();
  }
  private readonly disconnect = () => {
    this.controller.abort();
    // Retain capacity until the provider acknowledges cancellation.
    if (!this.working) this.dispose();
  };
  dispose(): void {
    clearTimeout(this.inputTimer);
    clearTimeout(this.responseTimer);
    this.request.raw.off('aborted', this.disconnect);
    this.reply.raw.off('close', this.disconnect);
    this.releaseCapacity();
  }
  private releaseCapacity(): void {
    if (!this.released) { this.released = true; this.release(); }
  }
}
