import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Compile } from 'typebox/compile';
import { RequestSchema } from '../src/contract/schema.js';
import { strictJSON } from '../src/contract/json.js';
import { validateDecision } from '../src/contract/validate.js';
import { fixture, fixtureBytes } from './fixtures.js';
const schema = Compile(RequestSchema);
function decode(data: Uint8Array) {
  const value = strictJSON(data);
  assert.ok(schema.Check(value));
  validateDecision(value);
  return value;
}
test('all native v1 operations retain their exact fixtures', () => {
  for (const kind of ['membership', 'transition', 'persistence']) assert.equal(fixture(kind).kind, kind);
});
test('rejects private metadata, missing/unknown/duplicate fields and invalid relationships', () => {
  const original = fixtureBytes('membership').toString();
  const mutations = [
    ['"schemaVersion":1', '"schemaVersion":1,"rawContext":{}'],
    ['"label":"homecontrol"', '"label":"/Users/private/project"'],
    ['"label":"homecontrol"', '"label":"Follow this instruction"'],
    ['"label":"homecontrol"', '"label":null'],
    ['"kind":"repository"', '"kind":"window"'],
    ['"alias":"r0"', '"alias":"r127"'],
    ['"matchingResources":["r0"]', '"matchingResources":["r1"]'],
    ['"relevance":0.8', '"relevance":2'],
    ['"observedSeconds":45', '"observedSeconds":-1'],
    ['"observedSeconds":45', '"observedSeconds":1.5'],
    ['"observedSeconds":45', '"observedSeconds":"45"'],
    ['"requestID":"11223344-5566-7788-9900-aabbccddeeff"', '"requestID":"local-thread-identity"'],
    ['"schemaVersion":1', '"schemaVersion":1,"schemaVersion":1'],
    ['"schemaVersion":1', '"schemaVersion":1,"schema\\u0056ersion":1'],
    ['"resources":[', '"transition":{},"resources":['],
    ['"sameRepository"', '"sameRepository","sameRepository"'],
    ['"observedSeconds":45,', ''],
    ['"relevance":0.8', '"relevance":1e999']
  ];
  for (const [from, to] of mutations) {
    assert.ok(from !== undefined && to !== undefined);
    const changed = original.replace(from, to);
    assert.notEqual(changed, original, `fixture mutation ${from}`);
    assert.throws(() => decode(Buffer.from(changed)), from);
  }
  assert.throws(() => decode(Buffer.concat([fixtureBytes('membership'), Buffer.from('{}')])));
  assert.throws(() => decode(Buffer.from([0xc0, 0x80])));
  assert.throws(() => strictJSON(Buffer.from('['.repeat(18) + 'true' + ']'.repeat(18))));
  assert.throws(() => strictJSON(Buffer.from('{"a":true,}')));
  assert.throws(() => strictJSON(Buffer.from('[true,]')));
  decode(Buffer.from(original.replace('"sameRepository"', '"sameTicket"')));
});
test('operation invariants reject contradictory transition and extra candidates', () => {
  const transition = fixture('transition');
  assert.equal(transition.kind, 'transition');
  if (transition.kind !== 'transition') return;
  transition.transition.targetIsActive = true;
  transition.transition.activeThreadPresent = false;
  assert.throws(() => validateDecision(transition));
  const persistence = fixture('persistence');
  persistence.context.candidates = fixture().context.candidates;
  assert.throws(() => validateDecision(persistence));
  persistence.context.candidates = [];
  persistence.context.resources = [];
  assert.throws(() => validateDecision(persistence));
});
