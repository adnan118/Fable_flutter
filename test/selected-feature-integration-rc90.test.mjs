import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {copyFileSync,mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname,join,resolve} from 'node:path';
import {auditSelectedFeatureIntegration,formatIntegrationGapReport} from '../tools/audit-selected-feature-integration.mjs';

const repo=resolve('.');
const save=(root,p,val)=>{
  const target=join(root,p);
  mkdirSync(dirname(target),{recursive:true});
  writeFileSync(target,typeof val==='string'?val:JSON.stringify(val,null,2)+'\n');
};
function fixture(selected=['notifications','deeplinks']){
  const root=mkdtempSync(join(tmpdir(),'fable-rc90-'));
  const master='docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json';
  const full=join(root,master);
  mkdirSync(dirname(full),{recursive:true});
  copyFileSync(master,full);
  save(root,'.fable/mobile-features.json',{
    schemaVersion:2,kind:'fable.mobile-feature-selection',
    features:selected,selectionSource:'explicit-test'});
  save(root,'assets/config/backend.json',{
    schemaVersion:1,kind:'fable.mobile-backend-configuration',
    backend:{kind:'other',adapter:'openapi',status:'ready'},contractImported:true});
  for(const id of selected){
    save(root,'packages/features/fable_'+id+'/pubspec.yaml','name: fable_'+id+'\n');
  }
  return root;
}
function external(root,operations,bindings={}){
  const sourceHash='a'.repeat(64),operationsHash=createHash('sha256')
    .update(JSON.stringify(operations)).digest('hex');
  save(root,'assets/contracts/external-operations.json',{
    schemaVersion:1,kind:'fable.external-operation-catalog',
    adapter:'openapi',sourceHash,operationsHash,baseUrl:'https://api.example.test',
    operations});
  save(root,'assets/config/feature-operations.json',{
    schemaVersion:1,kind:'fable.feature-operation-bindings',
    adapter:'openapi',sourceHash,operationsHash,bindings});
}
test('RC90 warns on selected Other Backend with no contract, but does not invent Fable routes',()=>{
  const root=fixture();
  try{
    const report=auditSelectedFeatureIntegration(root);
    assert.equal(report.selectedFeatureCount,2);
    assert.equal(report.backendKind,'other');
    const notice=report.features.find(f=>f.id==='notifications');
    assert.equal(notice.state,'MISSING');
    assert.ok(notice.missing.some(e=>e.code==='EXTERNAL_API_CATALOG_MISSING'));
    assert.ok(notice.missing.some(e=>e.code==='PER_FEATURE_REQUIREMENTS_NOT_DECLARED'));
    assert.ok(notice.missing.some(e=>e.code==='LIVE_E2E_NOT_VERIFIED'));
    assert.equal(report.features.find(f=>f.id==='deeplinks').state,'CLIENT_ONLY_NO_BACKEND_REQUIRED');
    const text=formatIntegrationGapReport(report);
    assert.match(text,/notifications/);
    assert.match(text,/EXTERNAL_API_CATALOG_MISSING/);
    assert.doesNotMatch(text,/\/auth\/login/);
  }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC90 gives method/path and per-DTO exact deficits on partially mapped service',()=>{
  const root=fixture(['notifications']);
  try{
    const operations=[
      {operationId:'external.notices.list',method:'GET',path:'/notices',auth:'bearer'},
    ];
    external(root,operations,{
      notifications:{list:'external.notices.list'},
    });
    save(root,'.fable/feature-integration-requirements.json',{
      schemaVersion:1,kind:'fable.feature-integration-requirements',
      features:{notifications:{needsBackend:true,operations:[
        {operationId:'external.notices.list',method:'GET',path:'/notices',
          requestDto:'docs/notification-list.dto.json',responseDto:'docs/notification-response.dto.json',
          errors:'401,403,429',permissions:'notifications:read',
          frontendFile:'packages/features/fable_notifications/lib/list.dart',
          testFile:'packages/features/fable_notifications/test/list_test.dart'},
        {operationId:'external.notices.mark-read',method:'PATCH',path:'/notices/{id}/read',
          requestDto:'docs/mark-read-request.dto.json',responseDto:'docs/mark-read-response.dto.json',
          errors:'401,404,409',permissions:'notifications:update',
          frontendFile:'packages/features/fable_notifications/lib/mark_read.dart',
          testFile:'packages/features/fable_notifications/test/mark_read_test.dart'},
      ]}},
    });
    const report=auditSelectedFeatureIntegration(root);
    const f=report.features[0];
    assert.equal(f.state,'PARTIAL');
    assert.equal(f.sourceMappedOperations,1);
    assert.ok(f.missing.some(x=>x.code==='REQUIRED_OPERATION_MISSING'&&
      x.operationId==='external.notices.mark-read'&&x.detail.includes('PATCH /notices/{id}/read')));
    assert.ok(f.missing.some(x=>x.code==='EVIDENCE_FILE_NOT_FOUND'));
    assert.ok(f.missing.some(x=>x.code==='REQUIRED_OPERATION_UNBOUND'===false));
    assert.ok(!f.missing.some(x=>x.code==='REQUIRED_OPERATION_MISSING'&&
      x.operationId==='external.notices.list'));
  }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC90 rejects unknown Backend mappings, a forged catalog hash and runtime E2E declaration',()=>{
  const root=fixture(['notifications']);
  try{
    external(root,[{operationId:'ext.list',method:'GET',path:'/notices',auth:'bearer'}],
      {notifications:{list:'ext.list'}});
    const config=join(root,'assets/contracts/external-operations.json');
    const forged=JSON.parse(readFileSync(config,'utf8'));
    forged.operations[0].method='POST';
    save(root,'assets/contracts/external-operations.json',forged);
    assert.throws(()=>auditSelectedFeatureIntegration(root),/malformed\/stale/);
    external(root,[{operationId:'ext.list',method:'GET',path:'/notices',auth:'bearer'}],
      {notifications:{list:'ext.list'}});
    save(root,'.fable/feature-integration-requirements.json',{
      schemaVersion:1,kind:'fable.feature-integration-requirements',
      features:{notifications:{needsBackend:true,liveE2EVerified:true,operations:[
        {operationId:'ext.list',method:'GET',path:'/notices',
          requestDto:'schema',responseDto:'schema',errors:'401',permissions:'view',
          frontendFile:'test/list.dart',testFile:'test/list_test.dart'}]}}
    });
    const f=auditSelectedFeatureIntegration(root).features[0];
    assert.ok(f.missing.some(x=>x.code==='LIVE_E2E_NOT_VERIFIED'));
    assert.equal(f.liveE2EVerified,false);
  }finally{rmSync(root,{recursive:true,force:true});}
});
test('RC90 inspects explicitly selected custom feature instead of silently hiding it',()=>{
  const root=fixture(['custom_orders']);
  try{
    const report=auditSelectedFeatureIntegration(root);
    const row=report.features[0];
    assert.equal(row.id,'custom_orders');
    assert.equal(row.state,'MISSING');
    assert.ok(row.missing.some(x=>x.code==='PER_FEATURE_REQUIREMENTS_NOT_DECLARED'));
  }finally{rmSync(root,{recursive:true,force:true});}
});
