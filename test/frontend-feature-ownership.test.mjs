import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {chooseFrontendFeature,reviewFrontendChoices} from '../tools/frontend-owned-features.mjs';
import {tmpdir} from 'node:os';
import {
  FEATURE_IDS,FEATURE_OWNERSHIP,classifyFeatureDecisions,
} from '../tools/frontend-feature-ownership.mjs';
import {
  frontendOwnedDefaults,readFrontendOwnedDecisions,
  saveFrontendOwnedDecisions,updateFrontendOwnedChoice,
} from '../tools/frontend-owned-decisions.mjs';

const server=['auth','support','social','realtime','messaging','payments','content'];
const client=['offline','deeplinks'];
const hybrid=FEATURE_IDS.filter(x=>!server.includes(x)&&!client.includes(x));
const declared={
  schemaVersion:1,source:'backend-installed-capabilities',
  enabled:['auth','profile','localization','access_control'],
  disabled:server.filter(x=>x!=='auth').concat(hybrid.filter(x=>!['profile','localization','access_control'].includes(x))),
  clientOnlyReview:client,
};
test('All features are explicitly owned by server / frontend / hybrid',()=>{
  assert.equal(FEATURE_IDS.length,17);
  for(const id of server)assert.equal(FEATURE_OWNERSHIP[id],'server');
  for(const id of client)assert.equal(FEATURE_OWNERSHIP[id],'client');
  for(const id of hybrid)assert.equal(FEATURE_OWNERSHIP[id],'hybrid');
  const policy=classifyFeatureDecisions(declared);
  assert.deepEqual(policy.backendPruneEligible,server.filter(x=>x!=='auth'));
  for(const id of client.concat(hybrid)){
    assert.equal(policy.byId[id].retainPackage,true);
    assert.equal(policy.byId[id].backendPruneEligible,false);
  }
  assert.ok(policy.visibleBackendFeatures.includes('auth'));
  assert.ok(!policy.visibleBackendFeatures.includes('notifications'));
});
test('Missing capability never erases frontend/hybrid source',()=>{
  const policy=classifyFeatureDecisions(declared,{mode:'explicit',features:['offline','deeplinks','media']});
  assert.equal(policy.byId.offline.retainPackage,true);
  assert.equal(policy.byId.deeplinks.retainPackage,true);
  assert.equal(policy.byId.media.retainPackage,true);
  assert.equal(policy.byId.media.defaultBackendUiVisible,false);
  assert.throws(()=>classifyFeatureDecisions(declared,{mode:'explicit',features:['payments']}),/does not support/);
});
test('Independent Flutter choices survive imports with a matching project ID',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-owned-choices-'));
  try{
    const defaults=frontendOwnedDefaults('my-project');
    assert.equal(defaults.choices.offline.enabled,null);
    assert.equal(defaults.choices.notifications.enabled,null);
    saveFrontendOwnedDecisions(root,defaults,{apply:true});
    updateFrontendOwnedChoice(root,'my-project','offline',true,{apply:true});
    updateFrontendOwnedChoice(root,'my-project','notifications',false,{apply:true});
    const current=readFrontendOwnedDecisions(root,'my-project');
    assert.equal(current.choices.offline.enabled,true);
    assert.equal(current.choices.notifications.enabled,false);
    assert.equal(JSON.parse(readFileSync(join(root,'assets/config/frontend-owned-decisions.json'))).choices.offline.enabled,true);
    assert.throws(()=>readFrontendOwnedDecisions(root,'another-project'),/another project/);
    assert.throws(()=>updateFrontendOwnedChoice(root,'my-project','payments',true,{apply:true}),/Not a Flutter-owned feature/);
    assert.ok(existsSync(join(root,'.fable/frontend-owned-decisions.json')));
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('Flutter-only choices need explicit consent and never touch Backend fields',async()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-native-settings-'));
  try{
    saveFrontendOwnedDecisions(root,frontendOwnedDefaults('project'),{apply:true});
    let prompts=0;
    const cancelled=await chooseFrontendFeature(root,'project',{
      feature:'offline',state:'on',ask:async()=>{prompts++;return 'لا';},show:()=>{},
    });
    assert.equal(cancelled.applied,false);
    assert.equal(readFrontendOwnedDecisions(root,'project').choices.offline.enabled,null);
    const accepted=await chooseFrontendFeature(root,'project',{
      feature:'offline',state:'on',ask:async()=>{prompts++;return 'اعتمد';},show:()=>{},
    });
    assert.equal(accepted.applied,true);
    assert.equal(prompts,2);
    assert.equal(reviewFrontendChoices(root,'project').rows.find(x=>x.id==='offline').decision,'ENABLED');
    await assert.rejects(chooseFrontendFeature(root,'project',{
      feature:'payments',state:'on',ask:async()=> 'اعتمد',
    }),/Only frontend-only or hybrid/);
  }finally{rmSync(root,{recursive:true,force:true});}
});
