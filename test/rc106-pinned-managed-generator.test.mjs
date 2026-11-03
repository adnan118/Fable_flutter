import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,existsSync,readFileSync,writeFileSync,mkdirSync,symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {
  planManagedScopedOperations,renderManagedScopedDart,
  generatePinnedManagedScopedOperations,collectManagedSelectedFeatures,
  writeManagedScopedOutput,OUTPUT,
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

test('RC107 a disabled feature is removed from all selected manifests, never once only',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc107-selection-'));
  const save=(path,value)=>{
    const output=join(root,path);mkdirSync(dirname(output),{recursive:true});
    writeFileSync(output,JSON.stringify(value));
  };
  try{
    save('.fable/mobile-features.json',{features:['billing','billing']});
    save('.fable/project-features.json',{features:['billing','billing']});
    save('.fable/frontend-owned-decisions.json',{
      kind:'fable.flutter-owned-decisions',choices:{billing:{enabled:false}},
    });
    assert.deepEqual(collectManagedSelectedFeatures(root),[]);
    save('.fable/frontend-owned-decisions.json',{
      kind:'fable.flutter-owned-decisions',choices:{billing:{enabled:true}},
    });
    assert.deepEqual(collectManagedSelectedFeatures(root),['billing']);
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC107 apply is idempotent but never overwrites existing manual or outdated bindings',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc107-write-'));
  try{
    const file=join(root,OUTPUT);
    const content=renderManagedScopedDart(
      [{feature:'billing',operationId:'billing.list',
        method:'GET',path:'/billing/invoices'}],HASH);
    assert.equal(writeManagedScopedOutput(file,content),true);
    assert.equal(writeManagedScopedOutput(file,content),false);
    const changed=content+'// manually edited\n';
    assert.throws(()=>writeManagedScopedOutput(file,changed),/Existing scoped bindings differ/);
    assert.equal(readFileSync(file,'utf8'),content);
    writeFileSync(file,'// human-written repository data');
    assert.throws(()=>writeManagedScopedOutput(file,content),/Existing scoped bindings differ/);
    assert.equal(readFileSync(file,'utf8'),'// human-written repository data');
    assert.throws(()=>writeManagedScopedOutput(file,'not wizard generated'),
      /Only reviewed Fable-generated/);
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC107 output refuses a symlink, preserving target content',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc107-symlink-'));
  try{
    const file=join(root,OUTPUT),target=join(root,'human-notes.txt');
    mkdirSync(dirname(file),{recursive:true});
    writeFileSync(target,'human data');
    symlinkSync(target,file);
    assert.throws(()=>writeManagedScopedOutput(file,renderManagedScopedDart([],HASH)),
      /Refusing to follow a symlink/);
    assert.equal(readFileSync(target,'utf8'),'human data');
  }finally{rmSync(root,{recursive:true,force:true});}
});
