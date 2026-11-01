import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {checkParity,validateMaster,auditBackendManifests} from '../tools/verify-feature-parity-master.mjs';

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
