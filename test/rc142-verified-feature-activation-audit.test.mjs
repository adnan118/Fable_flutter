import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const features=[
 'auth','profile','notifications','media','localization','support','social',
 'biometrics','realtime','deeplinks','messaging','location','payments','offline',
 'analytics','content','access_control'
];
const verified=new Set(['auth','profile','notifications','localization','content']);
test('RC142 all 17 source capability modules stay installed, not deleted',()=>{
  const registry=read('lib/src/generated/feature_registry.dart');
  for(const id of features)assert.ok(registry.includes(id==='access_control'
    ?'accessControlFeature':id==='deeplinks'?'deeplinksFeature':
      id+'Feature'),id);
});
test('RC142 only verified Fable consumer screens can render on home and push',()=>{
  const app=read('lib/src/app.dart');
  const core=read('packages/fable_core/lib/src/fable_contract.dart');
  const feature=read('packages/fable_feature_contract/lib/fable_feature_contract.dart');
  assert.ok(app.includes('feature.canLaunchFable(snapshot.fableContract!)'));
  assert.ok(app.includes('fableApiBase.isNotEmpty && feature.canLaunchFable(fable)'));
  assert.ok(feature.includes('bool canLaunchFable(FableContract contract) => false;'));
  assert.ok(core.includes('backendVisibleFeatureIds?.contains(featureId) ?? false'));
  assert.equal(core.includes('backendVisibleFeatureIds?.contains(featureId) ?? true'),false);
});
test('RC142 exactly five reviewed consumer pages, no keyword-only fake workflow',()=>{
  let count=0;
  for(const id of features){
    const dart=read('packages/features/fable_'+id+'/lib/fable_'+id+'.dart');
    const enabled=dart.includes('bool canLaunchFable(FableContract contract)');
    if(enabled)count++;
    assert.equal(enabled,verified.has(id),id);
  }
  assert.equal(count,5);
});
test('RC142 no finance, messaging or support action guessed from keywords',()=>{
  for(const id of ['payments','support','messaging']){
    const source=read('packages/features/fable_'+id+'/lib/fable_'+id+'.dart');
    assert.ok(!source.includes('bool canLaunchFable(FableContract contract)'));
  }
});
