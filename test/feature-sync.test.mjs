import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,join,dirname} from 'node:path';
import {syncProjectFeatures,planFeatureSync} from '../tools/sync-project-features.mjs';

const hash='e'.repeat(64);
const write=(root,path,content)=>{
  const dest=join(root,path);mkdirSync(dirname(dest),{recursive:true});
  writeFileSync(dest,typeof content==='string'?content:JSON.stringify(content));
};
function fixture(){
  const root=mkdtempSync(join(tmpdir(),'fable-feature-sync-'));
  write(root,'assets/contracts/contract.json',{project:{id:'my-backend'},contractHash:hash});
  write(root,'.fable/mobile-features.json',{schemaVersion:2,selectionSource:'preset:platform'});
  write(root,'.fable/project-features.json',{schemaVersion:1,features:[{id:'my-custom-feature'}]});
  write(root,'lib/src/generated/feature_registry.dart','// old registry\n');
  write(root,'pubspec.yaml',`name: demo
dependencies:
  fable_auth:
    path: packages/features/fable_auth
  fable_notifications:
    path: packages/features/fable_notifications
  fable_support:
    path: packages/features/fable_support
  fable_offline:
    path: packages/features/fable_offline
  fable_access_control:
    path: packages/features/fable_access_control
`);
  write(root,'lib/src/app.dart',`import 'package:flutter/material.dart';
// FABLE_PUSH_IMPORT_BEGIN
import 'package:fable_notifications/fable_notifications.dart';
// FABLE_PUSH_IMPORT_END
// FABLE_PUSH_ROUTES_BEGIN
void pushNotificationOnly() {}
// FABLE_PUSH_ROUTES_END
// FABLE_PUSH_NAV_BEGIN
navigatorKey: someValue,
// FABLE_PUSH_NAV_END
`);
  for(const id of ['auth','notifications','support','offline','access_control']){
    write(root,`packages/features/fable_${id}/lib/fable_${id}.dart`,'// package stub\n');
  }
  const verified={kind:'fable.flutter-frontend-setup',source:'backend-contract-export',
    backendAuthority:true,projectId:'my-backend',contractHash:hash,projectBound:true,
    decisionSnapshot:{decisions:{frontendFeatures:{
      schemaVersion:1,source:'backend-installed-capabilities',
      enabled:['auth','profile','localization','access_control'],
      disabled:['notifications','support'],
      clientOnlyReview:['deeplinks','offline']
    }}}};
  return {root,verified};
}
test('Backend decisions hide inactive features, safely archive and prune unused project packages',()=>{
  const f=fixture();try{
    const preview=syncProjectFeatures(f.root,f.verified);
    assert.equal(preview.applied,false);
    assert.ok(preview.disabled.includes('notifications'));
    assert.ok(preview.disabled.includes('support'));
    assert.equal(preview.protectedProjectFeatureCount,1);
    const applied=syncProjectFeatures(f.root,f.verified,{apply:true,prune:true});
    assert.equal(applied.applied,true);
    assert.ok(applied.prunedPackages.includes('packages/features/fable_notifications'));
    assert.ok(applied.prunedPackages.includes('packages/features/fable_support'));
    assert.equal(existsSync(join(f.root,'packages/features/fable_notifications')),false);
    assert.equal(existsSync(join(f.root,'packages/features/fable_support')),false);
    assert.ok(existsSync(join(f.root,applied.backup,'lib/src/app.dart')));
    assert.ok(existsSync(join(f.root,'packages/features/fable_auth')));
    assert.ok(existsSync(join(f.root,'packages/features/fable_offline')));
    assert.ok(!applied.prunedPackages.includes('packages/features/fable_offline'));
    assert.ok(readFileSync(join(f.root,'pubspec.yaml'),'utf8').includes('fable_offline:'));
    assert.ok(existsSync(join(f.root,'packages/features/fable_access_control')));
    assert.ok(readFileSync(join(f.root,'lib/src/generated/feature_registry.dart'),'utf8').includes('authFeature'));
    assert.ok(!readFileSync(join(f.root,'lib/src/generated/feature_registry.dart'),'utf8').includes('notificationsFeature'));
    assert.ok(!readFileSync(join(f.root,'lib/src/app.dart'),'utf8').includes('package:fable_notifications'));
    assert.ok(readFileSync(join(f.root,'pubspec.yaml'),'utf8').includes('fable_auth:'));
    assert.ok(!readFileSync(join(f.root,'pubspec.yaml'),'utf8').includes('fable_notifications:'));
  }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('Referenced feature source is retained instead of deleted',()=>{
  const f=fixture();try{
    write(f.root,'lib/src/custom.dart',"import 'package:fable_support/fable_support.dart';\n");
    const applied=syncProjectFeatures(f.root,f.verified,{apply:true,prune:true});
    assert.ok(applied.blocked.some(x=>x.feature==='support'));
    assert.ok(existsSync(join(f.root,'packages/features/fable_support')));
  }finally{rmSync(f.root,{recursive:true,force:true});}
});
test('No feature pruning from unbound or inconsistent backend project',()=>{
  const f=fixture();try{
    f.verified.projectBound=false;
    assert.equal(planFeatureSync(f.root,f.verified).pruneAvailable,false);
    assert.throws(()=>syncProjectFeatures(f.root,f.verified,{apply:true}),/independently pinned/);
    f.verified.projectBound=true;
    f.verified.decisionSnapshot.decisions.frontendFeatures.enabled=['auth'];
    assert.throws(()=>planFeatureSync(f.root,f.verified),/Conflicting/);
  }finally{rmSync(f.root,{recursive:true,force:true});}
});

test('Reusable ci_fable template never has its feature packages physically pruned',()=>{
  const f=fixture();
  try{
    const pubspec=join(f.root,'pubspec.yaml');
    writeFileSync(pubspec,'name: ci_fable\n'+readFileSync(pubspec,'utf8'));
    write(f.root,'.fable/project-features.json',{schemaVersion:1,app:'apps/ci_fable',features:[]});
    assert.throws(()=>syncProjectFeatures(f.root,f.verified,{apply:true,prune:true}),
      /Refusing to prune the reusable ci_fable starter/);
    assert.ok(existsSync(join(f.root,'packages/features/fable_support')));
  }finally{rmSync(f.root,{recursive:true,force:true});}
});
