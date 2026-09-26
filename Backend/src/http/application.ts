import { createServer } from 'node:http';
import Fastify, { type FastifyError } from 'fastify';
import { TypeBoxValidatorCompiler, type TypeBoxTypeProvider } from '@fastify/type-provider-typebox';
import type { ClientCredentials } from '../access/credentials.js';
import { DecisionFailure, fail } from '../contract/failure.js';
import { strictJSON } from '../contract/json.js';
import { ErrorSchema, RequestSchema, ResponseSchema, type ClientAllowance, type DecisionProvider } from '../contract/schema.js';
import { validateDecision } from '../contract/validate.js';
import { RequestLifetime } from './request-lifetime.js';

/** HTTP dependencies supplied only by application composition. */
export interface HTTPDependencies {
  credentials: ClientCredentials; allowance: ClientAllowance; provider: DecisionProvider;
  maxInFlight: number; maxConnections: number; report: (category: string) => void;
}
/** Constructs the HTTP adapter; provider and Redis configuration remain at composition.
 * Keep registration and lifecycle hooks together so authentication, parsing and cleanup order is explicit.
 */
export function buildApplication(dependencies: HTTPDependencies) {
  const app = Fastify({
    logger: false, bodyLimit: 65536, requestTimeout: 3000,
    connectionTimeout: 7000, keepAliveTimeout: 1000, return503OnClosing: true,
    ajv: { customOptions: { coerceTypes: false, removeAdditional: false, useDefaults: false } },
    serverFactory: handler => {
      const server = createServer({ maxHeaderSize: 8192, headersTimeout: 2000,
        requestTimeout: 3000, connectionsCheckingInterval: 100 }, handler);
      server.maxConnections = dependencies.maxConnections;
      return server;
    }
  }).withTypeProvider<TypeBoxTypeProvider>();
  app.setValidatorCompiler(TypeBoxValidatorCompiler);
  app.removeAllContentTypeParsers();
  app.addContentTypeParser('application/json', { parseAs: 'buffer', bodyLimit: 65536 }, (_request, body, done) => {
    try { done(null, strictJSON(body as Buffer)); } catch (error) { done(error as Error); }
  });
  const lifetimes = new WeakMap<object, RequestLifetime>();
  let active = 0;
  app.addHook('onRequest', async (request, reply) => {
    reply.header('Cache-Control', 'no-store').header('Connection', 'close');
    const health = ['/health/live', '/health/ready'].includes(request.raw.url ?? '');
    if (health && request.method === 'GET') return;
    if (request.raw.url !== '/v1/decisions') fail(404, 'not_found');
    if (request.method !== 'POST') fail(405, 'method_not_allowed');
    const id = dependencies.credentials.authenticate(request.headers.authorization);
    await dependencies.allowance.consume(id);
    if (request.raw.destroyed || reply.raw.destroyed) fail(408, 'request_timeout');
    if (active >= dependencies.maxInFlight) fail(503, 'capacity_unavailable');
    active++;
    lifetimes.set(request, new RequestLifetime(request, reply, () => { active--; }));
    if (request.headers['content-type']?.split(';')[0]?.trim().toLowerCase() !== 'application/json') fail(415, 'json_required');
    const encoding = request.headers['content-encoding'];
    if (encoding !== undefined && encoding !== 'identity') fail(415, 'encoding_unsupported');
    if (Number(request.headers['content-length']) > 65536) fail(413, 'request_too_large');
  });
  app.addHook('onResponse', async request => { lifetimes.get(request)?.dispose(); });
  app.setErrorHandler((error, request, reply) => {
    lifetimes.get(request)?.dispose();
    const framework = error instanceof Error ? error as FastifyError : undefined;
    let failure: DecisionFailure;
    if (error instanceof DecisionFailure) failure = error;
    else if (framework?.code === 'FST_ERR_CTP_BODY_TOO_LARGE') failure = new DecisionFailure(413, 'request_too_large');
    else if (framework?.validation || framework?.statusCode === 400) failure = new DecisionFailure(400, 'invalid_request');
    else if (framework?.statusCode === 415) failure = new DecisionFailure(415, 'json_required');
    else { failure = new DecisionFailure(500, 'internal_error'); }
    if (failure.status >= 500) dependencies.report(failure.category);
    if (failure.status === 429) reply.header('Retry-After', '60');
    void reply.code(failure.status).send({ error: failure.category });
  });
  app.setNotFoundHandler((_request, reply) => { void reply.code(404).send({ error: 'not_found' }); });
  app.get('/health/live', async (_request, reply) => reply.code(204).send());
  app.get('/health/ready', async (_request, reply) => {
    try { await dependencies.allowance.ready(); return reply.code(204).send(); }
    catch { return reply.code(503).send(); }
  });
  app.post('/v1/decisions', { schema: { body: RequestSchema,
    response: { 200: ResponseSchema, '4xx': ErrorSchema, '5xx': ErrorSchema } } }, async (request, reply) => {
    const lifetime = lifetimes.get(request);
    if (!lifetime) fail(500, 'internal_error');
    try {
      const signal = lifetime.begin();
      validateDecision(request.body);
      const result = await dependencies.provider.decide(request.body, signal);
      if (signal.aborted || reply.raw.destroyed) fail(504, 'provider_timeout');
      return result;
    } finally { lifetime.complete(); }
  });
  return app;
}
