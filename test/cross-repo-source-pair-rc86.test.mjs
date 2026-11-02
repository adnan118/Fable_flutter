import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,copyFileSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {verifySourcePair} from '../tools/verify-cross-repo-source-pair.mjs';

const SOURCE_FILES=[
 'docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json',
 'docs/integrations/FABLE-AUTH-OPERATIONS-RC80.json',
 'docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json',
];
const setup=()=>{
 const root=mkdtempSync(join(tmpdir(),'fable-pair-rc86-'));
 for(const relative of SOURCE_FILES){
  const output=join(root,relative);
  mkdirSync(dirname(output),{recursive:true});
  copyFileSync(relative,output);
 }
 return root;
};
const json=(path)=>JSON.parse(readFileSync(path,'utf8'));
const patch=(root,path,fn)=>{
 const abs=join(root,path);
 const data=json(abs);
 fn(data);
 writeFileSync(abs,JSON.stringify(data,null,2));
};

test('RC86 source pair is pinned to private Backend and includes all 40 Auth routes, but claims no E2E',()=>{
 const report=verifySourcePair({frontendRoot:process.cwd()});
 assert.equal(report.sourceOnly,true);
 assert.equal(report.sourceReviewed,17);
 assert.equal(report.notDecided,23);
 assert.equal(report.featureFamilies,17);
 assert.equal(report.liveE2EAccepted,0);
 assert.equal(report.authSourceBlobVerified,false);
 assert.equal(report.otherBackendMfaApproved,false);
});

test('RC86 refuses a stale Backend commit, false MFA readiness, or invented E2E',()=>{
 for(const change of [
  (root)=>patch(root,SOURCE_FILES[0],x=>x.backend.sourceCommitAtAudit='0'.repeat(40)),
  (root)=>patch(root,SOURCE_FILES[0],x=>x.counts.liveE2EAccepted=17),
  (root)=>patch(root,SOURCE_FILES[1],x=>x.operations[0].realE2EVerified=true),
  (root)=>patch(root,SOURCE_FILES[1],x=>x.operations[0].externalBackendMapped=true),
  (root)=>patch(root,SOURCE_FILES[1],x=>x.operations[0].wizardDecisionReviewed=true),
  (root)=>patch(root,SOURCE_FILES[2],x=>x.features.pop()),
 ]){
  const root=setup();
  try {
   change(root);
   assert.throws(()=>verifySourcePair({frontendRoot:root}),/SOURCE_PAIR_RC86/);
  }finally {rmSync(root,{recursive:true,force:true});}
 }
});
