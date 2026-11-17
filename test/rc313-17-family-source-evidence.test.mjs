import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectBuiltInFamilyBinding} from '../tools/audit-17-family-source-evidence-rc313.mjs';

function fixture(id){
  const pkg='fable_'+id;
  const varName=id.replace(/_([a-z])/g,(_,c)=>c.toUpperCase())+'Feature';
  return {
    pubspec:'name: sample\ndependencies:\n  flutter:\n    sdk: flutter\n  '+pkg+':\n    path: packages/features/'+pkg+'\n',
    registry:"import 'package:"+pkg+'/'+pkg+".dart';\n"+
      'const List<FableFeature> installedFeatures = <FableFeature>[\n'+
      '  '+varName+',\n];\n',
    packagePubspec:'name: '+pkg+'\n',
  };
}
test('RC313 source inventory accepts canonical feature pubspec and registry only',()=>{
  for(const id of ['auth','access_control','analytics','deeplinks']){
    const f=fixture(id);
    assert.deepEqual(inspectBuiltInFamilyBinding(
      f.pubspec,f.registry,f.packagePubspec,id),[]);
    assert.ok(inspectBuiltInFamilyBinding(
      f.pubspec.replace('packages/features/','packages/untrusted/'),
      f.registry,f.packagePubspec,id).length);
    const variable=id.replace(/_([a-z])/g,(_,letter)=>letter.toUpperCase())+'Feature';
    assert.ok(inspectBuiltInFamilyBinding(
      f.pubspec,f.registry.replace(variable,'rogueFeature'),
      f.packagePubspec,id).length);
  }
});
test('RC313 refuses duplicate dependency/import/entry or wrong package identity',()=>{
  const f=fixture('payments');
  assert.ok(inspectBuiltInFamilyBinding(
    f.pubspec+f.pubspec,f.registry,f.packagePubspec,'payments').length);
  assert.ok(inspectBuiltInFamilyBinding(
    f.pubspec,f.registry+f.registry,f.packagePubspec,'payments').length);
  assert.ok(inspectBuiltInFamilyBinding(
    f.pubspec,f.registry,'name: unrelated\n','payments').length);
});
