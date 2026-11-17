import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync,mkdirSync,writeFileSync,rmSync,symlinkSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {
  discoverGeneratedFeatureDartTests,buildOneCommandPlan,
  evaluateOneCommandPlan,runFableOneCommand,flutterChildSpec,
} from '../tools/fable-one-command.mjs';

const SHA='a'.repeat(64);
function fixture(fn,{features=['notes_ci','bookings']}={}){
  const root=mkdtempSync(join(tmpdir(),'fable-rc373-'));
  const generated=join(root,'generated');
  const put=(file,data='ok')=>{
    const full=join(generated,file);
    mkdirSync(join(full,'..'),{recursive:true});
    writeFileSync(full,data);
    return full;
  };
  try{
    put('pubspec.yaml','name: generated_fable\n');
    put('assets/config/backend.json','{}');
    put('assets/contracts/contract.json','{}');
    put('lib/src/generated/feature_registry.dart','const features = [];\n');
    put('.fable/project-features.json',
      JSON.stringify({schemaVersion:1,features}));
    for(const id of features)
      put('packages/features/fable_'+id+'/test/'+id+'_get_dto_test.dart',
        'void main() {}\n');
    writeFileSync(join(root,'package.json'),JSON.stringify({
      name:'rc373-test-host',packageManager:'pnpm@12.10.1',
      scripts:{},
    }));
    return fn({root,generated,put});
  }finally{rmSync(root,{recursive:true,force:true});}
}
const defaultInputs=generated=>({
  generatedFlutterRoot:generated,projectId:'rc373-genuine-project',
  contractHash:SHA,
});
const plan=(root,generated,inputs=defaultInputs(generated))=>
  buildOneCommandPlan({root,inputs,backendRoot:null,packageScripts:{},
    safeTestRead:()=>'',gitTestDiscovery:()=>({
      files:[],rejected:[],gitInventoryVerified:false,
    }),
  });
test('RC373 inventories exactly selected feature Dart test folders, not only host tests',()=>{
  fixture(({generated})=>{
    const r=discoverGeneratedFeatureDartTests(generated);
    assert.equal(r.featureCount,2);
    assert.equal(r.testFileCount,2);
    assert.deepEqual(r.paths,[
      'packages/features/fable_notes_ci/test',
      'packages/features/fable_bookings/test',
    ]);
  });
});
test('RC373 genuine generated project has explicit analyze and feature Flutter test steps',()=>{
  fixture(({root,generated})=>{
    const p=plan(root,generated);
    const w5=p.plan.find(x=>x.id==='W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT');
    const analyze=p.plan.find(x=>x.id==='W5_GENERATED_PROJECT_FLUTTER_ANALYZE');
    const dart=p.plan.find(x=>x.id==='W6_GENERATED_FEATURE_FLUTTER_TEST');
    assert.ok(p.plan.indexOf(w5)<p.plan.indexOf(analyze));
    assert.ok(p.plan.indexOf(w5)<p.plan.indexOf(dart));
    assert.equal(analyze.root,generated);
    assert.equal(dart.root,generated);
    assert.deepEqual(analyze.args,['analyze']);
    assert.deepEqual(dart.args,['test',
      'packages/features/fable_notes_ci/test',
      'packages/features/fable_bookings/test']);
    assert.equal(analyze.blockReason,null);
    assert.equal(dart.blockReason,null);
    assert.equal(p.generatedFeatureCount,2);
    assert.equal(p.generatedDartTestsDiscovered,2);
    assert.deepEqual(flutterChildSpec(dart,{platform:'win32'}),{
      command:'cmd.exe',args:['/d','/s','/c',
        'flutter test packages/features/fable_notes_ci/test packages/features/fable_bookings/test'],
    });
  });
});
test('RC373 no real signed project blocks BOTH generated Flutter checks',()=>{
  const p=plan('/tmp/missing-fable-rc373',null,{});
  for(const id of [
    'W5_GENERATED_PROJECT_FLUTTER_ANALYZE',
    'W6_GENERATED_FEATURE_FLUTTER_TEST',
  ])assert.match(p.plan.find(x=>x.id===id).blockReason,
    /REAL_SIGNED_GENERATED_FLUTTER_PROJECT_REQUIRED/);
});
test('RC373 malformed and duplicate selections fail closed, not tests-as-passed',()=>{
  fixture(({generated,put})=>{
    for(const selected of [['notes_ci','notes_ci'],['../secret'],[]]){
      put('.fable/project-features.json',
        JSON.stringify({schemaVersion:1,features:selected}));
      assert.throws(()=>discoverGeneratedFeatureDartTests(generated),
        /DUPLICATE|INVALID_SELECTED|UNSAFE/);
    }
  });
});
test('RC373 a missing selected feature test directory blocks local native tests',()=>{
  fixture(({root,generated})=>{
    rmSync(join(generated,'packages/features/fable_notes_ci/test'),
      {recursive:true});
    const p=plan(root,generated);
    for(const id of [
      'W5_GENERATED_PROJECT_FLUTTER_ANALYZE',
      'W6_GENERATED_FEATURE_FLUTTER_TEST',
    ])assert.equal(p.plan.find(x=>x.id===id).blockReason,
      'GENERATED_FEATURE_TEST_INVENTORY_MISSING_OR_UNSAFE');
  });
});
test('RC373 a symlinked generated feature test is never accepted',{
  skip:process.platform==='win32',
},()=>{
  fixture(({generated})=>{
    const file=join(generated,
      'packages/features/fable_notes_ci/test/notes_ci_get_dto_test.dart');
    rmSync(file);
    symlinkSync(join(generated,'missing-test.dart'),file);
    assert.throws(()=>discoverGeneratedFeatureDartTests(generated),
      /SYMLINKED_GENERATED_FEATURE_TEST/);
  });
});
test('RC373 the executor does not run generated Flutter on a failing W5 source audit',()=>{
  fixture(({root,generated})=>{
    const calls=[];
    const {report}=runFableOneCommand(root,{
      backendRoot:null,inputOverride:defaultInputs(generated),
      runner:step=>{
        calls.push(step.id);
        return {exitCode:step.id==='W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT'?2:0,
          signal:null,error:null,durationMs:1};
      },logger:()=>{},
    });
    assert.ok(calls.includes('W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT'));
    assert.ok(!calls.includes('W5_GENERATED_PROJECT_FLUTTER_ANALYZE'));
    assert.ok(!calls.includes('W6_GENERATED_FEATURE_FLUTTER_TEST'));
    for(const id of [
      'W5_GENERATED_PROJECT_FLUTTER_ANALYZE',
      'W6_GENERATED_FEATURE_FLUTTER_TEST',
    ]){
      const step=report.checks.find(x=>x.id===id);
      assert.equal(step.state,'BLOCKED');
      assert.equal(step.reason,'SIGNED_W5_GENERATED_SOURCE_AUDIT_NOT_PASSED');
    }
    assert.equal(report.productionReady,false);
  });
});
test('RC373 generated Flutter checks run only after an explicitly successful W5 audit',()=>{
  fixture(({root,generated})=>{
    const calls=[];
    const {report}=runFableOneCommand(root,{
      backendRoot:null,inputOverride:defaultInputs(generated),
      runner:step=>{
        calls.push(step.id);
        return {exitCode:0,signal:null,error:null,durationMs:1};
      },logger:()=>{},
    });
    const audit=calls.indexOf('W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT');
    const analyze=calls.indexOf('W5_GENERATED_PROJECT_FLUTTER_ANALYZE');
    const tests=calls.indexOf('W6_GENERATED_FEATURE_FLUTTER_TEST');
    assert.ok(audit>=0&&analyze>audit&&tests>audit);
    assert.equal(report.generatedSourceAuditPassed,true);
    assert.equal(report.generatedFeatureCount,2);
    assert.equal(report.generatedDartTestsDiscovered,2);
    assert.equal(report.productionReady,false);
    assert.equal(report.releaseDecision,'NO_GO');
  });
});
test('RC373 evaluating forged native process passes never waives failed signed W5 audit',()=>{
  fixture(({root,generated})=>{
    const p=plan(root,generated);
    const runs=[
      {id:'W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT',
        exitCode:2,signal:null,error:null},
      ...['W5_GENERATED_PROJECT_FLUTTER_ANALYZE',
        'W6_GENERATED_FEATURE_FLUTTER_TEST'].map(id=>({
        id,exitCode:0,signal:null,error:null,
      })),
    ];
    const r=evaluateOneCommandPlan(p,runs);
    for(const id of [
      'W5_GENERATED_PROJECT_FLUTTER_ANALYZE',
      'W6_GENERATED_FEATURE_FLUTTER_TEST',
    ])assert.equal(r.checks.find(x=>x.id===id).state,'BLOCKED');
    assert.equal(r.generatedSourceAuditPassed,false);
    assert.equal(r.productionReady,false);
  });
});
