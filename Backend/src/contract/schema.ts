import { Type, type Static } from 'typebox';

const seconds = Type.Integer({ minimum: 0, maximum: 2592000 });
const probability = Type.Number({ minimum: 0, maximum: 1 });
const object = { additionalProperties: false };
export const ResourceSchema = Type.Object({
  alias: Type.String({ pattern: '^r[0-9]+$' }),
  kind: Type.Enum(['application', 'window', 'browserPage', 'terminal', 'workingDirectory', 'repository', 'branch', 'file']),
  label: Type.Optional(Type.String({ pattern: '^[A-Za-z0-9._+/-]{1,128}$' })),
  observedSeconds: seconds
}, object);
const signals = ['sameRepository', 'sameBranch', 'sameDirectory', 'sameFile', 'sameBrowserPage', 'sameTicket', 'sharedLiveResource', 'recentActivity', 'conflictingRepository', 'conflictingBranch'] as const;
const CandidateSchema = Type.Object({
  alias: Type.String({ pattern: '^c[0-9]+$' }), relevance: probability,
  signals: Type.Array(Type.Enum(signals), { maxItems: 10, uniqueItems: true }),
  matchingResources: Type.Array(Type.String(), { maxItems: 128, uniqueItems: true }),
  secondsSinceActive: seconds
}, object);
const ContextSchema = Type.Object({
  schemaVersion: Type.Literal(1), observedSeconds: seconds,
  resources: Type.Array(ResourceSchema, { maxItems: 128 }),
  candidates: Type.Array(CandidateSchema, { maxItems: 8 })
}, object);
const common = {
  schemaVersion: Type.Literal(1),
  requestID: Type.String({ pattern: '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' }),
  context: ContextSchema
};
export const RequestSchema = Type.Union([
  Type.Object({ ...common, kind: Type.Literal('membership') }, object),
  Type.Object({ ...common, kind: Type.Literal('transition'), transition: Type.Object({
    activeThreadPresent: Type.Boolean(), targetIsActive: Type.Boolean(), membershipConfidence: probability
  }, object) }, object),
  Type.Object({ ...common, kind: Type.Literal('persistence'), resourceAlias: Type.Literal('r0') }, object)
]);
const response = { schemaVersion: Type.Literal(1), requestID: common.requestID, confidence: probability };
export const ResponseSchema = Type.Union([
  Type.Object({ ...response, kind: Type.Literal('membership'), target: Type.String() }, object),
  Type.Object({ ...response, kind: Type.Literal('transition'), shouldTransition: Type.Boolean() }, object),
  Type.Object({ ...response, kind: Type.Literal('persistence'), disposition: Type.Enum(['durable', 'sessionOnly', 'discard']) }, object)
]);
export const ErrorSchema = Type.Object({ error: Type.String() }, object);
export type DecisionRequest = Static<typeof RequestSchema>;
export type DecisionResponse = Static<typeof ResponseSchema>;
export type Resource = Static<typeof ResourceSchema>;
/** Supplies a judgment without application policy or graph mutation. */
export interface DecisionProvider { decide(input: DecisionRequest, signal: AbortSignal): Promise<DecisionResponse>; }
/** Consumes an atomic allowance shared across API replicas. */
export interface ClientAllowance { consume(clientID: string): Promise<void>; ready(): Promise<void>; }
