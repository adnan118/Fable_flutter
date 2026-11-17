import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Deferred source regression. Full contract-fixture and project acceptance
// suites must run separately; this test is intentionally not executed here.
test('RC369 W3 OpenAPI operation IDs have a dedicated project-route uniqueness gate',()=>{
  const source=readFileSync(new URL('../tools/verify-fable-contract.mjs',import.meta.url),'utf8');
  assert.match(source,/const seenProjectOperationIds=new Set\(\)/);
  assert.match(source,/seenProjectOperationIds\.has\(info\.operationId\)/);
  assert.match(source,/seenProjectOperationIds\.add\(info\.operationId\)/);
  assert.match(source,/fail\('duplicate_project_operation_id'\)/);
});
