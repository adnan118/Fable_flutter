import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const load=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const src=load('packages/features/fable_messaging/lib/src/messaging_repository.dart');
const dart=load('packages/features/fable_messaging/test/messaging_contract_test.dart');
const runner=load('tools/fable-one-command.mjs');

test('RC226 client send must require actual enforced authentication',()=>{
  assert.match(src,/op\.method != 'POST' \|\| !op\.requiresAuth \|\| !op\.enforceAuth/);
  assert.ok(src.includes('op.credentialHeader != null'));
});
test('RC226 mixed-case webhook paths and operation IDs fail client validation',()=>{
  assert.ok(src.includes('op.path.toLowerCase()'));
  assert.ok(src.includes('op.id.toLowerCase()'));
  assert.ok(src.includes("route.contains('/webhooks/')"));
  assert.ok(src.includes("operationId.contains('webhook')"));
});
test('RC226 messaging remains a single no-retry verified POST',()=>{
  const a=src.slice(src.indexOf('Future<void> send('));
  assert.equal((a.match(/gateway\.execute\(/g)||[]).length,1);
  assert.ok(a.includes('No automatic retry'));
});
test('RC226 four native contract tests cover weak auth and valid send',()=>{
  assert.equal((dart.match(/test\('/g)||[]).length,4);
  assert.ok(dart.includes("mixed-case inbound webhook names"));
  assert.ok(dart.includes('requiresAuth:true,enforceAuth:true'));
});
test('RC226 the same pnpm fable:all runs messaging tests',()=>{
  assert.ok(runner.includes('packages/features/fable_messaging/test/messaging_contract_test.dart'));
});
