import { fail } from './failure.js';
import type { DecisionRequest, Resource } from './schema.js';

/** Enforces relationships and privacy restrictions beyond structural schema validation. */
export function validateDecision(input: DecisionRequest): void {
  const invalid = () => fail(400, 'invalid_request');
  const aliases = new Set<string>();
  input.context.resources.forEach((resource, index) => {
    if (resource.alias !== `r${index}` || !validLabel(resource)) invalid();
    aliases.add(resource.alias);
  });
  input.context.candidates.forEach((candidate, index) => {
    if (candidate.alias !== `c${index}` || candidate.matchingResources.some(alias => !aliases.has(alias))) invalid();
  });
  if (input.kind !== 'membership' && input.context.candidates.length !== 0) invalid();
  if (input.kind === 'transition' && input.transition.targetIsActive && !input.transition.activeThreadPresent) invalid();
  if (input.kind === 'persistence' && input.context.resources.length === 0) invalid();
}
function validLabel(resource: Resource): boolean {
  const label = resource.label;
  if (label === undefined) return true;
  if (['window', 'terminal', 'workingDirectory'].includes(resource.kind)) return false;
  if (resource.kind === 'branch') return !label.startsWith('/') && !label.endsWith('/') && !label.includes('..');
  if (label.includes('/')) return false;
  if (resource.kind === 'browserPage') return label.includes('.') && label === label.toLowerCase() && !label.split('.').includes('');
  return true;
}
