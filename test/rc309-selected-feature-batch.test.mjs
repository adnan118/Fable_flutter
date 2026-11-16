import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {planW5AppFeatureBinding} from '../tools/w5-app-feature-binding.mjs';
import {generateSelectedProjectFeatures} from '../tools/generate-selected-project-features-rc309.mjs';

test('RC309 composes multiple typed app bindings in-memory without overwriting core modules',()=>{
  let pubspec='name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n';
  let registry='import \'package:fable_feature_contract/fable_feature_contract.dart\';\n' +
    'const List<FableFeature> installedFeatures = <FableFeature>[\n  authFeature,\n];\n';
  for(const id of ['hotel_rooms','hotel_inventory','hotel_guests']){
    const result=planW5AppFeatureBinding({pubspec,registry,featureId:id});
    pubspec=result.pubspec;registry=result.registry;
  }
  for(const id of ['hotel_rooms','hotel_inventory','hotel_guests']){
    assert.match(pubspec,new RegExp('  fable_'+id+':'));
    assert.match(registry,new RegExp('import \\'package:fable_'+id));
  }
  assert.match(registry,/  authFeature,/);
  assert.equal((pubspec.match(/^dependencies:$/gm)||[]).length,1);
  assert.equal((registry.match(/installedFeatures = <FableFeature>\[/g)||[]).length,1);
});

test('RC309 refuses incomplete or unsigned projects before writing any package',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc309-'));
  try{
    mkdirSync(join(root,'.fable'));
    mkdirSync(join(root,'packages'));
    mkdirSync(join(root,'packages/features'));
    const original='{"schemaVersion":1,"features":["hotel_rooms"]}\n';
    writeFileSync(join(root,'.fable/project-features.json'),original);
    assert.throws(()=>generateSelectedProjectFeatures({
      root,expectedProjectId:'project-demo',
      expectedContractHash:'a'.repeat(64),apply:true,wireApp:true,
    }),/requires a real source file|non-symlink|missing/i);
    assert.equal(readFileSync(join(root,'.fable/project-features.json'),'utf8'),original);
  }finally{rmSync(root,{recursive:true,force:true});}
});
