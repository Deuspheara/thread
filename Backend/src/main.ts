import { ClientCredentials } from './access/credentials.js';
import { readConfiguration } from './config.js';
import { healthcheck } from './healthcheck.js';
import { buildApplication } from './http/application.js';
import { OpenRouterDecisions } from './openrouter/client.js';
import { RedisAllowance } from './rate/redis-allowance.js';

// The sole production composition root owns startup, dependencies and joined shutdown.
const report = (category: string) => { process.stderr.write(JSON.stringify({ category }) + '\n'); };
async function run(): Promise<void> {
  const config = readConfiguration(process.env);
  const credentials = new ClientCredentials(config.tokens);
  const allowance = new RedisAllowance(config.redisURL, report);
  const provider = new OpenRouterDecisions(config.key);
  const app = buildApplication({ credentials, allowance, provider, ...config, report });
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    const deadline = setTimeout(() => { report('shutdown_deadline'); app.server.closeAllConnections(); void provider.close(); }, 5000).unref();
    try { await app.close(); }
    finally { clearTimeout(deadline); allowance.close(); await provider.close(); }
  };
  const signal = () => { void stop().catch(() => { report('shutdown_failure'); process.exitCode = 1; }); };
  try {
    await allowance.connect();
    process.once('SIGTERM', signal);
    process.once('SIGINT', signal);
    await app.listen({ host: config.host, port: config.port });
    report('backend_started');
  } catch (error) { await stop(); throw error; }
}
if (process.argv[2] === 'healthcheck') process.exitCode = await healthcheck(process.env);
else {
  try { await run(); }
  catch { report('backend_unavailable'); process.exitCode = 1; }
}
