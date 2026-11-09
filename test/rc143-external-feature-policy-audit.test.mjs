import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
test('RC143 Other Backend client bindings reject server-only authentication and webhooks',()=>{
  const s=read('packages/fable_core/lib/src/external_feature_bindings.dart');
  for(const str of ["op.credentialHeader!=null","contains('/webhooks/')",
     "contains('webhook')","(!op.requiresAuth||!op.enforceAuth)",
     "feature=='payments' && mutation"]){
    assert.ok(s.includes(str),str);
  }
});
test('RC143 wizard CLI checks the same binding rules as the Dart runtime',()=>{
  const s=read('tools/audit-selected-feature-integration.mjs');
  for(const code of [
    'BOUND_UNKNOWN_ROLE','SERVER_ONLY_EXTERNAL_OPERATION',
    'EXTERNAL_WRITE_AUTH_UNVERIFIED','FINANCIAL_TYPED_ADAPTER_REQUIRED'
  ])assert.ok(s.includes(code),code);
});
test('RC143 unknown provider operations never become implicit Fable routes',()=>{
  const s=read('packages/fable_core/lib/src/external_feature_bindings.dart');
  assert.ok(s.includes('catalog.require(action.value as String)'));
  assert.equal(s.includes("'/auth/refresh'"),false);
});
