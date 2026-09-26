import { readFileSync } from 'node:fs';
import { Compile } from 'typebox/compile';
import { RequestSchema } from '../src/contract/schema.js';
import { strictJSON } from '../src/contract/json.js';
import { validateDecision } from '../src/contract/validate.js';
export function fixtureBytes(name: string): Buffer { return readFileSync(new URL(`fixtures/${name}.json`, import.meta.url)); }
const schema = Compile(RequestSchema);
export function fixture(kind = 'membership') {
  const value = strictJSON(fixtureBytes(kind));
  if (!schema.Check(value)) throw new Error('invalid fixture');
  validateDecision(value);
  return value;
}
export const token = 'a'.repeat(43);
export const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
