import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const source=read('packages/features/fable_profile/lib/src/external_profile_repository.dart');
const dart=read('packages/features/fable_profile/test/external_profile_repository_test.dart');
const runner=read('tools/fable-one-command.mjs');

test('RC224 personal profile GET requires authenticated, enforced per-user identity',()=>{
  assert.match(source,/operation\.method != 'GET' \|\| !operation\.requiresAuth/);
  assert.match(source,/!operation\.enforceAuth \|\| operation\.credentialHeader != null/);
});
test('RC224 profile mapping never accepts a path parameter or unbound operation',()=>{
  assert.match(source,/operation\.path\.contains\('\{'\)/);
  assert.ok(source.includes('!catalog.supports(operationId)'));
});
test('RC224 existing projection fingerprint and selector defenses remain unchanged',()=>{
  assert.ok(source.includes("value['sourceHash'] != catalog.sourceHash"));
  assert.ok(source.includes("value['operationsHash'] != catalog.operationsHash"));
  assert.ok(source.includes('_secretField.hasMatch(key)'));
  assert.ok(source.includes('FableImmutablePayload.object(data)'));
});
test('RC224 Flutter profile fixture uses approved Bearer credential',()=>{
  assert.ok(dart.includes("'auth':'bearer'"));
  assert.ok(dart.includes("RC224 personal profile refuses anonymous or provider-wide credential GET"));
  assert.ok(dart.includes("for(final auth in ['none','provider'])"));
});
test('RC224 user-specific profile project remains available with good contract',()=>{
  assert.ok(dart.includes("RC224 verified Bearer profile GET stays supported"));
  assert.equal((dart.match(/test\('/g)||[]).length,5);
});
test('RC224 one pnpm command includes actual Other Backend profile validation tests',()=>{
  assert.ok(runner.includes("packages/features/fable_profile/test/external_profile_repository_test.dart"));
});
