import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname,join} from 'node:path';
import {managedScopedOperationEvidenceGaps}
  from '../tools/audit-selected-feature-integration.mjs';

const requirements={
  operationId:'business.dashboard',
  method:'GET',
  path:'/business/dashboard',
  managedEntityScope:true,
  frontendFile:'lib/src/features/business/dashboard_repo.dart',
  testFile:'test/business_dashboard_test.dart',
};
function fixture(){
  const root=mkdtempSync(join(tmpdir(),'rc105-scope-'));
  function write(name,content){
    const file=join(root,name);
    mkdirSync(dirname(file),{recursive:true});
    writeFileSync(file,content);
  }
  return {root,write,cleanup:()=>rmSync(root,{recursive:true,force:true})};
}
test('RC105 explicit Fable scoped operation requires contract-bound source and tests',()=>{
  const env=fixture();
  try{
    assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'fable',requirements),
      ['MANAGED_SCOPE_SOURCE_BINDING_UNVERIFIED',
       'MANAGED_SCOPE_TEST_BINDING_UNVERIFIED']);
    env.write(requirements.frontendFile,`
      const scoped=FableManagedScopedOperation(
        operationId:'business.dashboard',
        method:'GET',path:'/business/dashboard',
        contractHash:backendContractHash,
      );
      return repo.executeBoundInStore(store,scoped);
    `);
    env.write(requirements.testFile,`
      test('managed scope',()=>{
        expect(repo.executeBoundInStore(store,binding),isA<Future>());
        // business.dashboard
      });
    `);
    assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'fable',requirements),[]);
  } finally {env.cleanup();}
});
test('RC105 Other Backend never inherits Fable managed scope',()=>{
  const env=fixture();
  try{
    assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'other',requirements),
      ['FABLE_MANAGED_SCOPE_NOT_AVAILABLE_FOR_OTHER_BACKEND']);
  } finally {env.cleanup();}
});
test('RC105 rejects managed scope for Auth, Admin and global permission routes',()=>{
  const env=fixture();
  try {
    for(const path of ['/auth/me','/permissions/me','/admin/users',
      '/managed-entities/public/{slug}']){
      assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'fable',
        {...requirements,path}),['MANAGED_SCOPE_OPERATION_FORBIDDEN']);
    }
    assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'fable',
      {...requirements,managedEntityScope:'yes'}),['MANAGED_SCOPE_MODE_INVALID']);
    assert.deepEqual(managedScopedOperationEvidenceGaps(env.root,'fable',
      {...requirements,managedEntityScope:false}),[]);
  }finally{env.cleanup();}
});
