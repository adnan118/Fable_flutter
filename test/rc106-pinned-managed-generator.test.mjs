import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {
  planManagedScopedOperations,renderManagedScopedDart,
  generatePinnedManagedScopedOperations,OUTPUT,
} from '../tools/generate-managed-scoped-operations.mjs';

const HASH='a'.repeat(64);
const contract={
  kind:'fable.client-contract',contractHash:HASH,
  operations:[
    {operationId:'billing.list',method:'GET',path:'/billing/invoices',public:false},
    {operationId:'billing.update',method:'PATCH',path:'/billing/invoices/{id}',public:false},
    {operationId:'auth.me',method:'GET',path:'/auth/me',public:false},
    {operationId:'admin.list',method:'GET',path:'/admin/users',public:false},
    {operationId:'public.list',method:'GET',path:'/public/items',public:true},
  ],
};
const selected=['billing'];
function requirements(ops){
  return {
    schemaVersion:1,kind:'fable.feature-integration-requirements',
    features:{billing:{needsBackend:true,operations:ops}},
  };
}
const op={
  operationId:'billing.list',method:'GET',path:'/billing/invoices',
  managedEntityScope:true,
};

test('RC106 generates stable Dart constants ONLY for selected authenticated contract operations',()=>{
  const planned=planManagedScopedOperations(contract,requirements([op]),selected);
  assert.deepEqual(planned,[{feature:'billing',
    operationId:'billing.list',method:'GET',path:'/billing/invoices'}]);
  const dart=renderManagedScopedDart(planned,HASH);
  assert.match(dart,/FableManagedScopedOperation/);
  assert.match(dart,/operationId: "billing.list"/);
  assert.match(dart,/path: "\/billing\/invoices"/);
  assert.match(dart,new RegExp(HASH));
  assert.ok(!dart.includes('auth.me'));
  assert.equal(renderManagedScopedDart(planned,HASH),dart);
});

test('RC106 refuses invented method/path, anonymous, Auth, Admin and unsigned extra operations',()=>{
  for(const bad of [
    {...op,method:'POST'},
    {...op,path:'/billing/other'},
    {...op,operationId:'missing'},
    {...op,operationId:'auth.me',path:'/auth/me'},
    {...op,operationId:'admin.list',path:'/admin/users'},
    {...op,operationId:'public.list',path:'/public/items'},
    {...op,managedEntityScope:'true'},
  ]){
    assert.throws(()=>planManagedScopedOperations(contract,requirements([bad]),selected));
  }
  assert.throws(()=>planManagedScopedOperations(contract,requirements([op]),['profile']),
    /not explicitly selected/);
  assert.throws(()=>planManagedScopedOperations({...contract,contractHash:'wrong'},
    requirements([op]),selected));
});

test('RC106 never guesses scopes or generates extra header when no operation opted in',()=>{
  const declared=[
    {operationId:'billing.list',method:'GET',path:'/billing/invoices',
      managedEntityScope:false},
  ];
  const result=planManagedScopedOperations(contract,requirements(declared),selected);
  assert.deepEqual(result,[]);
  const code=renderManagedScopedDart(result,HASH);
  assert.doesNotMatch(code,/X-Fable-Managed-Entity-Id/);
  assert.doesNotMatch(code,/billing.list/);
});

test('RC106 dry-run/apply refuses a project without an independent verified pin',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc106-'));
  try {
    const file=join(root,OUTPUT);
    assert.throws(()=>generatePinnedManagedScopedOperations(root,{
      expectedProjectId:'project-A',expectedContractHash:HASH,apply:true,
    }),/Approved frontend setup/);
    assert.equal(existsSync(file),false);
    assert.throws(()=>generatePinnedManagedScopedOperations(root,{
      expectedProjectId:'',expectedContractHash:'invalid',apply:true,
    }),/Independent project ID/);
    assert.equal(existsSync(file),false);
  }finally{rmSync(root,{recursive:true,force:true});}
});
