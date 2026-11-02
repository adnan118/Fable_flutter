import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,rmSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {frontendOwnedDefaults,readFrontendOwnedDecisions,saveFrontendOwnedDecisions,
  DEFAULT_OFFLINE_SYNC_POLICY} from '../tools/frontend-owned-decisions.mjs';
import {approveOfflineSync,reviewOfflineSync} from '../tools/offline-sync-wizard.mjs';

test('RC89 default policy is approved, but new project needs opt-in to enable Offline',()=>{
  const initial=frontendOwnedDefaults('other-app');
  assert.equal(initial.choices.offline.enabled,null);
  assert.deepEqual(initial.offlineSync,DEFAULT_OFFLINE_SYNC_POLICY);
  assert.equal(initial.offlineSync.policy,'foreground_plus_background_best_effort');
  assert.equal(initial.offlineSync.guaranteedBackgroundExecution,false);
});

test('RC89 explicit consent preserves identity and never invents financial/Backend rights',async()=>{
 const root=mkdtempSync(join(tmpdir(),'fable-rc89-'));
 try{
  saveFrontendOwnedDecisions(root,frontendOwnedDefaults('project-a'),{apply:true});
  const refused=await approveOfflineSync(root,'project-a',{enabled:true,
    ask:async()=> 'لا',show:()=>{}});
  assert.equal(refused.cancelled,true);
  assert.equal(readFrontendOwnedDecisions(root,'project-a').choices.offline.enabled,null);
  const accepted=await approveOfflineSync(root,'project-a',{enabled:true,
    ask:async()=> 'اعتمد',show:()=>{}});
  assert.equal(accepted.applied,true);
  assert.equal(accepted.backendSecurityOverride,false);
  assert.equal(accepted.mutationContractVerified,false);
  assert.equal(reviewOfflineSync(root,'project-a').enabled,true);
  const disk=JSON.parse(readFileSync(join(root,'assets/config/frontend-owned-decisions.json')));
  assert.equal(disk.offlineSync.policy,'foreground_plus_background_best_effort');
  assert.equal(disk.offlineSync.writeReplay,'verified_backend_operation_only');
  await assert.rejects(approveOfflineSync(root,'project-b',{
    enabled:true,ask:async()=> 'اعتمد'}),/another project/);
  assert.throws(()=>saveFrontendOwnedDecisions(root,{
    ...disk,offlineSync:{...disk.offlineSync,guaranteedBackgroundExecution:true}},
    {apply:true}),/Invalid Offline\/Sync policy/);
  assert.throws(()=>saveFrontendOwnedDecisions(root,{
    ...disk,offlineSync:{...disk.offlineSync,writeReplay:'all_operations'}},
    {apply:true}),/Invalid Offline\/Sync policy/);
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC89 existing Flutter v1 choices read safely with default policy and no automatic opt-in',()=>{
 const root=mkdtempSync(join(tmpdir(),'fable-legacy-offline-'));
 try{
  const legacy=frontendOwnedDefaults('project-c');
  delete legacy.offlineSync;
  const path=join(root,'.fable/frontend-owned-decisions.json');
  mkdirSync(dirname(path),{recursive:true});
  writeFileSync(path,JSON.stringify(legacy));
  const loaded=readFrontendOwnedDecisions(root,'project-c');
  assert.equal(loaded.choices.offline.enabled,null);
  assert.equal(loaded.offlineSync.policy,'foreground_plus_background_best_effort');
  assert.equal(existsSync(join(root,'assets/config/frontend-owned-decisions.json')),false);
 }finally{rmSync(root,{recursive:true,force:true});}
});
