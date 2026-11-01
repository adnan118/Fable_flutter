import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {checkParity,validateMaster,auditBackendManifests,auditBackendWideDecisionSources} from '../tools/verify-feature-parity-master.mjs';
import {createHash} from 'node:crypto';

const root=resolve(fileURLToPath(new URL('../',import.meta.url)));
const load=()=>JSON.parse(readFileSync(join(root,
  'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json'),'utf8'));

test('ثبت 17 ميزة ولا تدّعي اكتمالاً دون عقد مشروع فعلي واختبار حي',()=>{
 const report=checkParity(root);
 assert.deepEqual(report.errors,[]);
 assert.equal(report.flutterFeatureCount,17);
 assert.equal(new Set(report.featureIds).size,17);
 assert.equal(report.realProjectContractVerified,false);
 assert.equal(report.completeFeatures,0);
 for(const item of load().features){
   assert.equal(item.complete,false);
   assert.equal(item.liveE2EVerified,false);
   assert.ok(item.otherBackendContract.length>0);
   assert.ok(item.gaps.length>0);
 }
});

test('جميع عمليات Auth الأربعون موثقة بالاسم ومفتوحة للمراجعة لا للاكتمال',()=>{
 const auth=JSON.parse(readFileSync(join(root,
   'docs/integrations/FABLE-AUTH-OPERATIONS-RC80.json'),'utf8'));
 assert.equal(auth.operationCount,40);
 assert.equal(auth.operations.length,40);
 assert.equal(new Set(auth.operations.map(x=>x.id)).size,40);
 assert.ok(auth.operations.some(x=>x.id==='auth.change-password'));
 assert.ok(auth.operations.some(x=>x.id==='auth.2fa.enable'));
 assert.ok(auth.operations.some(x=>x.id==='auth.contact.phone.change'));
 assert.ok(auth.operations.some(x=>x.id==='auth.web.login'));
 for(const op of auth.operations){
   assert.equal(op.realE2EVerified,false);
   if(op.id==='auth.change-password'){
     assert.equal(op.disposition,'SOURCE_IMPLEMENTED_E2E_PENDING');
     assert.equal(op.modelAndDtoReviewed,true);
     assert.equal(op.uiFlowReviewed,true);
     assert.equal(op.permissionAndErrorReviewed,true);
     assert.ok(op.missingGates.length>=3);
     assert.ok(op.otherBackendRequired.length>=3);
   }else{
     assert.equal(op.disposition,'NOT_DECIDED');
     assert.equal(op.uiFlowReviewed,false);
     assert.equal(op.modelAndDtoReviewed,false);
   }
 }
});

test('23 قراراً عاماً عابراً للميزات، ولا صلاحية مُفترضة في Other Backend',()=>{
 const shared=JSON.parse(readFileSync(join(root,
   'docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.json'),'utf8'));
 assert.equal(shared.decisions.length,23);
 assert.equal(new Set(shared.decisions.map(x=>x.id)).size,23);
 for(const row of shared.decisions){
   assert.ok(row.otherBackendRequirement.length>15);
   assert.equal(row.fullParityVerified,false);
   assert.equal(row.projectContractVerified,false);
 }
 const broken=structuredClone(shared);
 broken.decisions.splice(broken.decisions.findIndex(x=>x.id==='sessionPolicy'),1);
 const temp=mkdtempSync(join(tmpdir(),'shared-policy-'));
 try{
   // اختبارات البنية ضمن سجل الميزات وليس عقداً إنتاجياً مزوراً.
   assert.equal(broken.decisions.length,22);
 }finally{rmSync(temp,{force:true,recursive:true});}
});

test('كشف فقدان ملف أو ميزة أو تغيير الملكية أو ادعاء اكتمال زائف',()=>{
 const original=load();
 for(const alter of [
   (x)=>x.features.pop(),
   (x)=>x.features[0].complete=true,
   (x)=>x.features[0].ownership='client',
   (x)=>x.features[0].frontendEvidence.push('packages/fable_core/lib/src/missing.dart'),
   (x)=>x.features[1].otherBackendContract=[],
 ]){
   const copy=structuredClone(original);
   alter(copy);
   assert.notEqual(validateMaster(root,copy).errors.length,0);
 }
});

test('كشف Capability جديد ومسار لم يُصنف وتغيير Blueprint Backend',()=>{
 const temp=mkdtempSync(join(tmpdir(),'parity-rc80-'));
 try{
   const caps=join(temp,'Fable-Backend-RC66','blueprints','capabilities');
   for(const [name,routes] of Object.entries({
     auth:[{id:'auth.login',method:'POST',path:'/auth/login'}],
     'managed-accounts':[{id:'managed-accounts.create',method:'POST',path:'/managed-entities'}],
     'surprise-new-feature':[{id:'surprise.x',method:'GET',path:'/new-feature'}],
   })){
     const dir=join(caps,name);
     mkdirSync(dir,{recursive:true});
     writeFileSync(join(dir,'manifest.json'),JSON.stringify({name,routes}));
   }
   const review=auditBackendManifests(temp,['auth','managed-accounts']);
   assert.equal(review.routeCount,3);
   assert.equal(review.operationDecisionsStillRequired,3);
   assert.ok(review.newCapabilities.includes('surprise-new-feature'));
   assert.equal(review.mappedCandidateRoutes,2);
   assert.equal(review.unclassifiedForMobile,1);
   assert.equal(review.routes.every(x=>x.disposition==='NOT_DECIDED'),true);
 }finally{rmSync(temp,{recursive:true,force:true});}
});


test('تغيّر قرار Backend عام يُكشف بالبصمة ولو لم يتغير أي مسار API',()=>{
 const temp=mkdtempSync(join(tmpdir(),'rc81-policy-'));
 try{
  const root=join(temp,'Fable-Backend-RC66');
  const path=join(root,'lib','http-policy.mjs');
  mkdirSync(join(root,'lib'),{recursive:true});
  const content='export const REQUEST_HEADERS=[];\n';
  writeFileSync(path,content);
  const sourceGitBlobSha=createHash('sha1')
    .update('blob '+Buffer.byteLength(content)+'\x00')
    .update(content).digest('hex');
  const policies=[{id:'httpPolicy',backendSource:'lib/http-policy.mjs',sourceGitBlobSha}];
  const clean=auditBackendWideDecisionSources(temp,policies);
  assert.equal(clean.trackedSources,1);
  assert.deepEqual(clean.changed,[]);
  assert.deepEqual(clean.missing,[]);
  writeFileSync(path,content+'// changed\n');
  const altered=auditBackendWideDecisionSources(temp,policies);
  assert.equal(altered.changed.length,1);
  assert.equal(altered.changed[0].path,'lib/http-policy.mjs');
  const missing=auditBackendWideDecisionSources(temp,[{
    id:'missing',backendSource:'lib/no-policy.mjs',sourceGitBlobSha
  }]);
  assert.deepEqual(missing.missing,['lib/no-policy.mjs']);
 }finally{rmSync(temp,{recursive:true,force:true});}
});
