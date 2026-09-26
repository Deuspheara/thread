import { Type } from 'typebox';
import { Compile } from 'typebox/compile';
import { fail } from '../contract/failure.js';
import { strictJSON } from '../contract/json.js';
import type { DecisionRequest, DecisionResponse } from '../contract/schema.js';
import { buildQuestion } from './question.js';
const probability = Type.Number({ minimum: 0, maximum: 1 });
const wire = Compile(Type.Object({
  model: Type.String({ pattern: '^typesafe/jev-1\\.13(-[0-9]{8})?$' }),
  answers: Type.Object({ decision: Type.Union([
    Type.Object({ type: Type.Literal('noul'), noul: probability }),
    Type.Object({ type: Type.Literal('choice'), choice: Type.String(), confidence: probability,
      probabilities: Type.Record(Type.String(), probability) })
  ]) }, { additionalProperties: false })
}));
/** Returns the selected outcome probability, never distribution concentration. */
export function normalize(data: Uint8Array, input: DecisionRequest): DecisionResponse {
  const bad = () => fail(502, 'invalid_provider_response');
  let value: unknown;
  try { value = strictJSON(data); } catch { return bad(); }
  if (!wire.Check(value) || Object.hasOwn(value, 'error')) return bad();
  const answer = value.answers.decision;
  const base = { schemaVersion: 1 as const, requestID: input.requestID };
  if (input.kind === 'transition') {
    if (answer.type !== 'noul') return bad();
    const yes = answer.noul > 0.5;
    return { ...base, kind: input.kind, shouldTransition: yes, confidence: yes ? answer.noul : 1 - answer.noul };
  }
  if (answer.type !== 'choice') return bad();
  const criteria = buildQuestion(input).questions.decision.criteria;
  const chosen = answer.probabilities[answer.choice];
  if (!Object.hasOwn(criteria, answer.choice) || chosen === undefined || Object.keys(answer.probabilities).length !== Object.keys(criteria).length) return bad();
  let total = 0;
  for (const key of Object.keys(criteria)) {
    const probability = answer.probabilities[key];
    if (probability === undefined || probability > chosen + 0.000001) return bad();
    total += probability;
  }
  if (Math.abs(total - 1) > 0.02) return bad();
  if (input.kind === 'membership') return { ...base, kind: input.kind, target: answer.choice, confidence: chosen };
  if (!['durable', 'sessionOnly', 'discard'].includes(answer.choice)) return bad();
  return { ...base, kind: input.kind, disposition: answer.choice as 'durable' | 'sessionOnly' | 'discard', confidence: chosen };
}
