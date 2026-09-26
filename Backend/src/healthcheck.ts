import { request } from 'node:http';
/** Checks Redis-backed readiness without credentials or a provider call. */
export async function healthcheck(environment: NodeJS.ProcessEnv): Promise<number> {
  const host = environment.THREAD_API_HOST === '0.0.0.0' ? '127.0.0.1' : environment.THREAD_API_HOST || '127.0.0.1';
  return new Promise(resolve => {
    const probe = request({ host, port: environment.THREAD_API_PORT || 8787, path: '/health/ready', method: 'GET',
      signal: AbortSignal.timeout(1000) }, response => {
      response.resume();
      resolve(response.statusCode === 204 ? 0 : 1);
    });
    probe.on('error', () => resolve(1));
    probe.end();
  });
}
