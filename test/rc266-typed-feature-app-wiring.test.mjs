import test from 'node:test';
import assert from 'node:assert/strict';
import {planW5AppFeatureBinding,w5FeatureNames} from '../tools/w5-app-feature-binding.mjs';
import {wiredTypedProjectFeatures} from '../tools/sync-project-features.mjs';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';

const pubspec="name: project_mobile\ndependencies:\n  flutter:\n    sdk: flutter\n  fable_core:\n    path: packages/fable_core\n";
const registry="import 'package:fable_feature_contract/fable_feature_contract.dart';\nimport 'package:fable_auth/fable_auth.dart';\n\nconst List<FableFeature> installedFeatures = <FableFeature>[\n  authFeature,\n];\n";

test('RC266 wires a real typed selected feature to the app without replacing builtin features',()=>{
  const result=planW5AppFeatureBinding({
    featureId:'orders_ci',pubspec,registry,
  });
  assert.match(result.pubspec,/fable_orders_ci:\n    path: packages\/features\/fable_orders_ci/);
  assert.match(result.registry,/import 'package:fable_orders_ci\/fable_orders_ci.dart';/);
  assert.match(result.registry,/  ordersCiProjectFeature,/);
  assert.match(result.registry,/  authFeature,/);
  assert.match(result.pubspec,/  fable_core:/);
  assert.equal(pubspec.includes('fable_orders_ci'),false);
  assert.equal(registry.includes('ordersCiProjectFeature'),false);
});

test('RC266 refuses overwriting existing user registration or dependency',()=>{
  const wired=planW5AppFeatureBinding({
    featureId:'orders_ci',pubspec,registry,
  });
  for(const bad of [
    {pubspec:wired.pubspec,registry},
    {pubspec,registry:wired.registry},
    {pubspec:wired.pubspec,registry:wired.registry},
  ]){
    assert.throws(()=>planW5AppFeatureBinding({...bad,featureId:'orders_ci'}),
      /already wired/);
  }
});

test('RC266 refuses source template, malformed registry and path injection',()=>{
  for(const featureId of ['../evil','foo/bar','auth; rm -rf', 'Foo','a__b']){
    assert.throws(()=>w5FeatureNames(featureId),/invalid/);
  }
  assert.throws(()=>planW5AppFeatureBinding({
    featureId:'orders_ci',pubspec:pubspec.replace('project_mobile','ci_fable'),
    registry,
  }),/reusable ci_fable/);
  assert.throws(()=>planW5AppFeatureBinding({
    featureId:'orders_ci',pubspec,registry:registry.replace(
      'installedFeatures = <FableFeature>[','installedFeatures = unknown['),
  }),/not canonical/);
});

test('RC266 remains Fable-only and does not add generic Backend endpoints',()=>{
  const result=planW5AppFeatureBinding({featureId:'orders_ci',pubspec,registry});
  assert.doesNotMatch(result.registry,/ExternalApi|Other Backend|\/auth\/login/);
});

test('RC266 later Backend feature sync discovers registered typed project launchers',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-w5-rc266-'));
  try{
    const binding=planW5AppFeatureBinding({
      featureId:'orders_ci',pubspec,registry,
    });
    const save=(path,data)=>{
      const file=join(root,path);
      mkdirSync(dirname(file),{recursive:true});
      writeFileSync(file,data);
    };
    save('pubspec.yaml',binding.pubspec);
    save('lib/src/generated/feature_registry.dart',binding.registry);
    save('packages/features/fable_orders_ci/lib/src/project_feature.dart',
      'const ordersCiProjectFeature=FableOrdersCiProjectFeature();');
    assert.deepEqual(wiredTypedProjectFeatures(root,['orders_ci']),['orders_ci']);
    assert.deepEqual(wiredTypedProjectFeatures(root,[]),[]);
    save('pubspec.yaml',pubspec);
    assert.throws(()=>wiredTypedProjectFeatures(root,['orders_ci']),
      /previously registered typed feature is incomplete/);
  }finally{
    rmSync(root,{recursive:true,force:true});
  }
});
