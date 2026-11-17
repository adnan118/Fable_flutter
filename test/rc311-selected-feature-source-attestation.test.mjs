import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {verifyRenderedFeatureTree,verifySelectedAppBindings} from
  '../tools/verify-selected-project-features-rc311.mjs';
import {planW5AppFeatureBinding} from '../tools/w5-app-feature-binding.mjs';

test('RC311 attests exactly rendered source and refuses uncontracted files',()=>{
  const root=mkdtempSync(join(tmpdir(),'fable-rc311-source-'));
  const dir=join(root,'packages/features/fable_hotel_rooms');
  const name='packages/features/fable_hotel_rooms/lib/fable_hotel_rooms.dart';
  const files=new Map([[name,'// verified source\n']]);
  try{
    mkdirSync(join(dir,'lib'),{recursive:true});
    writeFileSync(join(dir,'lib/fable_hotel_rooms.dart'),'// verified source\n');
    const verified=verifyRenderedFeatureTree(root,'hotel_rooms',files);
    assert.equal(verified.fileCount,1);
    assert.match(verified.sourceTreeSha256,/^[0-9a-f]{64}$/);
    writeFileSync(join(dir,'lib/rogue.dart'),'void rogue() {}\n');
    assert.throws(()=>verifyRenderedFeatureTree(root,'hotel_rooms',files),
      /extra package file/);
    rmSync(join(dir,'lib/rogue.dart'));
    writeFileSync(join(dir,'lib/fable_hotel_rooms.dart'),'// tampered\n');
    assert.throws(()=>verifyRenderedFeatureTree(root,'hotel_rooms',files),
      /differs from signed render/);
  }finally{rmSync(root,{recursive:true,force:true});}
});

test('RC311 verifies canonical multi-feature app binding and detects missing entries',()=>{
  let pubspec='name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n';
  let registry="import 'package:fable_feature_contract/fable_feature_contract.dart';\n"+
    'const List<FableFeature> installedFeatures = <FableFeature>[\n  authFeature,\n];\n';
  for(const featureId of ['hotel_rooms','hotel_guests']){
    const next=planW5AppFeatureBinding({pubspec,registry,featureId});
    pubspec=next.pubspec;registry=next.registry;
  }
  assert.doesNotThrow(()=>verifySelectedAppBindings(
    pubspec,registry,['hotel_rooms','hotel_guests']));
  assert.throws(()=>verifySelectedAppBindings(
    pubspec,registry.replace('  hotelGuestsProjectFeature,\n',''),
    ['hotel_rooms','hotel_guests']),/missing\/duplicate canonical feature registry/);
  assert.throws(()=>verifySelectedAppBindings(
    pubspec.replace('    path: packages/features/fable_hotel_rooms',
      '    path: packages/features/untrusted'),
    registry,['hotel_rooms','hotel_guests']),/missing\/duplicate canonical dependency/);
});
