import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {managedAccessContextBindingGaps} from '../tools/audit-selected-feature-integration.mjs';

test('Wizard audit recognizes the starter Managed Accounts / Access Control binding',()=>{
  assert.deepEqual(managedAccessContextBindingGaps(process.cwd()),[]);
});

test('Wizard audit fails closed when the shared managed context wiring is absent',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-managed-access-audit-'));
  try{
    const gaps=managedAccessContextBindingGaps(root);
    assert.ok(gaps.includes('APP_STORE_NAMESPACE'));
    assert.ok(gaps.includes('ACCESS_SESSION_INVALIDATION'));
    assert.ok(gaps.includes('GLOBAL_PERMISSION_BOUNDARY'));
    assert.ok(gaps.includes('MANAGED_ROLE_RESUME_REFRESH'));
    assert.ok(gaps.includes('SCOPED_DENIAL_CLEAR'));
    assert.ok(gaps.includes('MEMBER_ROUTE_STORE'));
    assert.ok(gaps.includes('MEMBER_PAGE_SELECTION_REVISION'));
    assert.ok(gaps.includes('MEMBER_PAGE_CONFIRMATION_GUARD'));
    assert.ok(gaps.includes('MEMBER_PAGE_RESUME_ROLE_REVALIDATION'));
    assert.ok(gaps.includes('MANAGED_PARENT_SCOPE_GUARD'));
    assert.ok(gaps.includes('MANAGED_PARENT_INVITE_GUARD'));
    assert.equal(gaps.length,18);
  }finally{rmSync(root,{recursive:true,force:true});}
});
