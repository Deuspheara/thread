import { Compile } from 'typebox/compile';
import { RequestSchema, type DecisionRequest } from './contract/schema.js';
import { validateDecision } from './contract/validate.js';
import { OpenRouterDecisions } from './openrouter/client.js';

// Explicit developer-only, potentially billable check using fictional metadata.
const kind = process.argv[2];
if (!['membership', 'transition', 'persistence'].includes(kind ?? '') || !process.env.OPENROUTER_API_KEY) {
  process.stderr.write('Export a provider key privately and choose membership, transition or persistence.\n');
  process.exitCode = 1;
} else {
  const input = { schemaVersion: 1, requestID: '11223344-5566-7788-9900-aabbccddeeff', kind,
    context: { schemaVersion: 1, observedSeconds: 45,
      resources: [{ alias: 'r0', kind: 'repository', label: 'fictional-project', observedSeconds: 45 }], candidates: [] },
    ...(kind === 'transition' ? { transition: { activeThreadPresent: true, targetIsActive: false, membershipConfidence: 0.98 } } : {}),
    ...(kind === 'persistence' ? { resourceAlias: 'r0' } : {})
  };
  const schema = Compile(RequestSchema);
  const provider = new OpenRouterDecisions(process.env.OPENROUTER_API_KEY);
  try {
    if (!schema.Check(input)) throw new Error('invalid fixture');
    validateDecision(input as DecisionRequest);
    const result = await provider.decide(input as DecisionRequest, AbortSignal.timeout(3000));
    process.stdout.write(JSON.stringify({ kind: result.kind, confidence: result.confidence }) + '\n');
  } catch { process.stderr.write('provider_check_failed\n'); process.exitCode = 1; }
  finally { await provider.close(); }
}
