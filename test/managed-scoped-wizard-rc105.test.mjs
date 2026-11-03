import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {auditSelectedFeatureIntegration} from '../tools/audit-selected-feature-integration.mjs';

function save(root,name,content){
  const file=join(root,name);
  mkdirSync(dirname(file),{recursive:true});
  writeFileSync(file,typeof content==='string'?content:JSON.stringify(content)+'\n');
}
function fixture(provider='fable'){
  const root=mkdtempSync(join(tmpdir(),'fable-rc105-wizard-'));
  save(root,'.fable/mobile-features.json',{
    schemaVersion:2,kind:'fable.mobile-feature-selection',
    features:['notifications'],selectionSource:'rc105-simulation'});
  save(root,'packages/features/fable_notifications/pubspec.yaml','name: fable_notifications\n');
  save(root,'assets/config/backend.json',{
    schemaVersion:1,kind:'fable.mobile-backend-configuration',
    backend:{kind:provider,adapter:provider==='fable'?'fable-contract':'openapi',status:'pending'},
    contractImported:false});
  const operation={
    operationId:'entity.notes',method:'GET',path:'/managed-entities/notes',
    managedEntityScoped:true,frontendFile:'lib/src/generated/notes_repository.dart',
    requestDto:'dto/notes-request.json',responseDto:'dto/notes-response.json',
    errors:'401,403,409',permissions:'entity.notes.read',
    testFile:'test/notes_repository_test.dart',
  };
  const write=()=>save(root,'.fable/feature-integration-requirements.json',{
    schemaVersion:1,kind:'fable.feature-integration-requirements',
    features:{notifications:{needsBackend:true,operations:[operation]}}});
  write();
  return {root,operation,write};
}
function codes(root){
  return auditSelectedFeatureIntegration(root).features[0].missing.map(x=>x.code);
}

test('RC105 Wizard reports missing scoped executor for an explicitly scoped Fable operation',()=>{
  const {root}=fixture();
  try{
    assert.ok(codes(root).includes('MANAGED_SCOPED_EXECUTOR_NOT_USED'));
    save(root,'lib/src/generated/notes_repository.dart',
      'FableManagedEntityExecutor(gateway,store).execute(operationId);\n');
    assert.ok(!codes(root).includes('MANAGED_SCOPED_EXECUTOR_NOT_USED'));
    // Static source gate is not live role/DB E2E acceptance.
    assert.ok(codes(root).includes('LIVE_E2E_NOT_VERIFIED'));
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC105 never applies Fable managed-entity headers to Other Backend',()=>{
  const {root}=fixture('other');
  try{
    assert.ok(codes(root).includes('FABLE_SCOPE_NOT_APPLICABLE_TO_OTHER_BACKEND'));
    assert.ok(!codes(root).includes('MANAGED_SCOPED_EXECUTOR_NOT_USED'));
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC105 does not guess managed scoping from a URL or operation label',()=>{
  const x=fixture();
  try{
    delete x.operation.managedEntityScoped;
    x.write();
    assert.ok(!codes(x.root).includes('MANAGED_SCOPED_EXECUTOR_NOT_USED'));
    x.operation.managedEntityScoped='true';
    x.write();
    assert.ok(codes(x.root).includes('MANAGED_SCOPING_DECLARATION_INVALID'));
  }finally{rmSync(x.root,{recursive:true,force:true});}
});
