import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {
  discoverExistingNodeTests,detectBackendRoot,
  buildOneCommandPlan,evaluateOneCommandPlan,
} from '../tools/fable-one-command.mjs';
import {runSingleCommand} from '../tools/run-fable-all.mjs';

const base={root:'/tmp/rc217-flutter',backendRoot:'/tmp/rc217-backend',
  flutterAvailable:false};
const SHAs={expectedBackendSha:'a'.repeat(40),
  expectedFlutterSha:'b'.repeat(40)};
const CLOSURE={kind:'fable.final-closure-audit',releaseDecision:'NO_GO',
  counts:{families:17,sourceGapItems:60,crossCuttingItems:10,
    wizardScenarios:12,outstanding:82}};
const tests={scripts:{
 'test:closeout':'node --test test/first.test.mjs test/second.test.mjs',
 'test:w6:auth:source':'node --test test/second.test.mjs test/third.test.mjs',
 'test:w6:auth':'flutter test packages/fable_core/test/example.dart',
 'test:unsafe':'node --test ../secrets/unsafe.test.mjs',
 'test:weird':'node --test test/example.test.mjs; rm -rf /',
}};
function plan({inputs={},scripts={},available=false,exist=()=>true}={}){
 return buildOneCommandPlan({...base,packageScripts:scripts,
   inputs,flutterAvailable:available,exists:exist,
   safeTestRead:()=>'',gitTestDiscovery:()=>({
     files:[],rejected:[],gitInventoryVerified:false,
   })});
}
const evaluated=(p,runs,closure=CLOSURE)=>evaluateOneCommandPlan(p,runs,{
 closure,backendCheckout:{localMainVerified:true,independentPinVerified:false},
 flutterCheckout:{localMainVerified:true,independentPinVerified:false},
});
test('RC217 one pnpm command collects all prior direct Node test scripts exactly once',()=>{
 const x=discoverExistingNodeTests(tests.scripts,()=>true);
 assert.deepEqual(x.paths,[
  'test/first.test.mjs','test/second.test.mjs','test/third.test.mjs']);
 assert.ok(x.unsupported.includes('test:unsafe'));
 assert.ok(x.unsupported.includes('test:weird'));
});
test('RC217 single command includes both Backend W1/W2 fast and full real generation',()=>{
 const p=plan();
 assert.deepEqual(p.plan.find(x=>x.id==='BACKEND_W1_W2_FAST').args,
  ['tools/fable-w1-w2-one-shot.mjs','--fast','--json']);
 assert.deepEqual(p.plan.find(x=>x.id==='BACKEND_W1_W2_FULL').args,
  ['tools/fable-w1-w2-one-shot.mjs','--full','--json']);
});
test('RC217 includes W0, W2, W3, W4, W5 and native W6–W7 checks in one run',()=>{
 const p=plan();
 assert.equal(p.plan.length,11);
 for(const part of ['W2_GENERATED_BACKEND_ARTIFACT_AUDIT',
   'W3_REAL_BACKEND_FLUTTER_HANDOFF',
   'W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS',
   'W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT',
   'W0_HISTORICAL_82_ITEM_AUDIT',
   'W6_W7_NATIVE_AUTH_NOTIFICATIONS_WIDGET',
   'W7_FLUTTER_ANALYZE','W7_FULL_FLUTTER_TEST'])
  assert.ok(p.plan.some(x=>x.id===part),part);
});
test('RC217 all independent Fable exports and W3 pins are optional, not invented',()=>{
 const p=plan();
 assert.equal(p.profileExportsProvided,0);
 assert.ok(p.plan.find(x=>x.id==='W3_REAL_BACKEND_FLUTTER_HANDOFF')
  .blockReason.includes('INDEPENDENT'));
 assert.ok(p.plan.find(x=>x.id==='W2_GENERATED_BACKEND_ARTIFACT_AUDIT')
  .blockReason.includes('ACTUAL_GENERATED_BACKEND'));
});
test('RC217 no Backend checkout is blocked but Flutter Node tests remain runnable',()=>{
 const p=buildOneCommandPlan({root:'/tmp/flutter',
   packageScripts:{'test:source':'node --test test/example.test.mjs'},
   exists:()=>true,safeTestRead:()=>'',
   gitTestDiscovery:()=>({files:[],rejected:[],gitInventoryVerified:false})});
 assert.ok(p.plan.find(x=>x.id==='BACKEND_W1_W2_FAST').blockReason);
 assert.equal(p.plan.find(x=>x.id==='NODE_ALL_EXISTING_TEST_SCRIPTS')
  .blockReason,null);
});
test('RC217 zero generated Flutter project must never make W5 false PASS',()=>{
 const p=plan();
 const r=evaluated(p,p.plan.map(x=>({id:x.id,exitCode:2,
  signal:null,error:null})));
 assert.equal(r.checks.find(x=>x.id==='W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT').state,
  'BLOCKED');
 assert.equal(r.productionReady,false);
});
test('RC217 a starter fixture that returns exit zero cannot pass W5 without real project pins',()=>{
 const p=plan();
 const r=evaluated(p,[{id:'W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT',
  exitCode:0,signal:null,error:null}]);
 assert.equal(r.checks.find(x=>x.id==='W5_COMPLETE_SELECTED_FEATURE_SOURCE_AUDIT')
  .state,'BLOCKED');
});
test('RC217 missing Fable exports still runs Other Wizard scenarios but marks W4 BLOCKED',()=>{
 const p=plan();
 const r=evaluated(p,[{id:'W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS',
   exitCode:2,signal:null,error:null}]);
 assert.equal(r.checks.find(x=>x.id==='W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS')
  .state,'BLOCKED');
 assert.equal(r.checks.find(x=>x.id==='W4_TWELVE_GUIDED_AGENT_WIZARD_SCENARIOS')
  .fullWizardMatrixAccepted,false);
});
test('RC217 historical 82-item strict audit fails closed as pending acceptance, not a regression',()=>{
 const p=plan();
 const r=evaluated(p,[{id:'W0_HISTORICAL_82_ITEM_AUDIT',exitCode:2,
  signal:null,error:null}]);
 assert.equal(r.checks.find(x=>x.id==='W0_HISTORICAL_82_ITEM_AUDIT').state,
  'BLOCKED');
 assert.equal(r.historical.outstanding,82);
 assert.equal(r.releaseDecision,'NO_GO');
});
test('RC217 nonzero test exit never counts as success',()=>{
 const p=plan({scripts:tests.scripts});
 const r=evaluated(p,[{id:'NODE_ALL_EXISTING_TEST_SCRIPTS',
  exitCode:7,signal:null,error:null}]);
 assert.equal(r.checks[0].state,'FAILED');
 assert.equal(r.counts.failed,1);
});
test('RC218 missing flutter is BLOCKED and incomplete Git test inventory stays PARTIAL',()=>{
 const p=plan({scripts:tests.scripts});
 const r=evaluated(p,[
  {id:'NODE_ALL_EXISTING_TEST_SCRIPTS',exitCode:0,signal:null,error:null},
  {id:'W7_FLUTTER_ANALYZE',exitCode:null,signal:null,error:'ENOENT'},
 ]);
 assert.equal(r.checks.find(x=>x.id==='NODE_ALL_EXISTING_TEST_SCRIPTS')
  .state,'PARTIAL');
 assert.equal(r.checks.find(x=>x.id==='W7_FLUTTER_ANALYZE').state,'BLOCKED');
});
test('RC217 passing all artificial local runs still cannot waive real devices/approval',()=>{
 const p=plan({scripts:tests.scripts,available:true});
 const r=evaluated(p,p.plan.map(x=>({id:x.id,exitCode:0,
  signal:null,error:null})));
 assert.equal(r.releaseDecision,'NO_GO');
 assert.equal(r.realAndroidVerified,false);
 assert.equal(r.realIosVerified,false);
 assert.equal(r.realProviderE2EVerified,false);
 assert.equal(r.independentReleaseApproved,false);
 assert.equal(r.realDeviceProviderAndHumanGates.length,5);
});
test('RC217 Backend sibling discovery uses only known sibling roots',()=>{
 const root='/my/projects/Fable_flutter';
 const out=detectBackendRoot(root,path=>
  path===join('/my/projects','Fable','Fable-Backend-RC66',
   'tools/fable-w1-w2-one-shot.mjs'));
 assert.equal(out,join('/my/projects','Fable','Fable-Backend-RC66'));
});
test('RC217 refuses extra command flags instead of requiring a confusing second invocation',()=>{
 assert.throws(()=>runSingleCommand(['--help']),/ONE_COMMAND_ONLY/);
});
test('RC217 discovers a complete three-profile source plan only from explicit source input',()=>{
 const profiles={};
 for(const key of ['minimal','standard','complex'])
  profiles[key]={source:'/tmp/real/'+key,
   expectedProjectId:'real-'+key,expectedContractHash:
     (key==='minimal'?'a':key==='standard'?'b':'c').repeat(64)};
 const p=plan({inputs:{...SHAs,fableProfiles:profiles},
  exist:()=>true});
 // Nonexistent fixtures are intentionally blocked; tests cannot make fake
 // paths into accepted real Backend exports just by naming them.
 assert.equal(p.profileExportsProvided,0);
});
