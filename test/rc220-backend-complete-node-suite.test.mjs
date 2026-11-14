import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildOneCommandPlan,evaluateOneCommandPlan,
} from '../tools/fable-one-command.mjs';

const ROOT='/tmp/fable-rc220-flutter';
const BACKEND='/tmp/fable-rc220-backend/Fable-Backend-RC66';
const testSources={
  flutter:['test/a.test.mjs','tools/b.test.mjs'],
  backend:['test/batch-aa.test.mjs','test/rc209.test.mjs'],
};
const basePlan=(opts={})=>buildOneCommandPlan({
  root:ROOT,backendRoot:BACKEND,
  packageScripts:{'test:core':'node --test test/a.test.mjs'},
  safeTestRead:()=>'',exists:()=>true,flutterAvailable:false,
  gitTestDiscovery:root=>({
    files:root===BACKEND?testSources.backend:testSources.flutter,
    rejected:[],gitInventoryVerified:true,
  }),
  ...opts,
});
const output=(plan,runs=[])=>evaluateOneCommandPlan(plan,runs,{
  closure:{kind:'fable.final-closure-audit',releaseDecision:'NO_GO',
    counts:{families:17,sourceGapItems:60,crossCuttingItems:10,
      wizardScenarios:12,outstanding:82}},
});
test('RC220 Flutter and Backend full historical Node tests both run in one plan',()=>{
  const p=basePlan();
  assert.equal(p.plan.length,12);
  assert.deepEqual(p.plan[0].args,[
    '--test','--test-concurrency=4','test/a.test.mjs','tools/b.test.mjs',
  ]);
  assert.deepEqual(p.plan[1].args,[
    '--test','--test-concurrency=4',
    'test/batch-aa.test.mjs','test/rc209.test.mjs',
  ]);
  assert.equal(p.backendTestsDiscovered,2);
  assert.equal(p.filesDiscovered,2);
});
test('RC220 private suite stays anchored to the Backend package cwd',()=>{
  const p=basePlan();
  assert.equal(p.plan[1].root,BACKEND);
  assert.equal(p.plan[0].root,ROOT);
});
test('RC220 original W1W2 fast and full still exist alongside the full historical suite',()=>{
  const p=basePlan();
  assert.deepEqual(p.plan.slice(2,4).map(x=>x.id),[
    'BACKEND_W1_W2_FAST','BACKEND_W1_W2_FULL',
  ]);
  assert.ok(p.plan[2].args.includes('--fast'));
  assert.ok(p.plan[3].args.includes('--full'));
});
test('RC220 missing private repository never counts a full Backend test PASS',()=>{
  const p=basePlan({backendRoot:null});
  assert.equal(p.backendTestsDiscovered,0);
  assert.match(p.plan[1].blockReason,/UNAVAILABLE/);
  const r=output(p,[{id:'BACKEND_ALL_TRACKED_NODE_TESTS',
    exitCode:0,signal:null,error:null}]);
  assert.equal(r.checks[1].state,'BLOCKED');
});
test('RC220 private test listing failure is transparently PARTIAL after a zero exit',()=>{
  const p=basePlan({gitTestDiscovery:root=>{
    if(root===BACKEND)return {
      files:['test/rc209.test.mjs'],rejected:[],gitInventoryVerified:false};
    return {files:testSources.flutter,rejected:[],gitInventoryVerified:true};
  }});
  const r=output(p,[{id:'BACKEND_ALL_TRACKED_NODE_TESTS',
    exitCode:0,signal:null,error:null}]);
  assert.equal(r.checks[1].state,'PARTIAL');
  assert.equal(r.completeBackendGitTestInventoryVerified,false);
});
test('RC220 an unsafe skipped Backend test cannot silently get complete status',()=>{
  const p=basePlan({
    safeTestRead:(root,path)=>{
      if(root===BACKEND&&path==='test/rc209.test.mjs')
        throw Error('unsafe symlink');
    },
  });
  assert.equal(p.backendTestsDiscovered,1);
  assert.ok(p.backendUnsafeTests.includes('UNSAFE_BACKEND_NODE_TEST:test/rc209.test.mjs'));
  const r=output(p,[{id:'BACKEND_ALL_TRACKED_NODE_TESTS',
    exitCode:0,signal:null,error:null}]);
  assert.equal(r.checks[1].state,'PARTIAL');
});
test('RC220 a genuine failing private Backend test still reports FAILED',()=>{
  const p=basePlan();
  const r=output(p,[{id:'BACKEND_ALL_TRACKED_NODE_TESTS',
    exitCode:1,signal:null,error:null}]);
  assert.equal(r.checks[1].state,'FAILED');
  assert.equal(r.counts.failed,1);
});
test('RC220 complete private test pass never implies production ready',()=>{
  const p=basePlan();
  const r=output(p,[{id:'BACKEND_ALL_TRACKED_NODE_TESTS',
    exitCode:0,signal:null,error:null}]);
  assert.equal(r.checks[1].state,'LOCAL_CHECK_PASS');
  assert.equal(r.backendTestsDiscovered,2);
  assert.equal(r.completeBackendGitTestInventoryVerified,true);
  assert.equal(r.productionReady,false);
  assert.equal(r.releaseDecision,'NO_GO');
});
test('RC220 summary preserves all W0 82 blockers and the device approvals',()=>{
  const p=basePlan();
  const r=output(p);
  assert.equal(r.historical.outstanding,82);
  assert.equal(r.realDeviceProviderAndHumanGates.length,5);
  assert.equal(r.independentReleaseApproved,false);
});
test('RC220 all legacy Flutter Node files are preserved while adding Backend files',()=>{
  const p=basePlan();
  assert.equal(p.unregisteredNodeTests,1);
  assert.equal(p.backendTestsDiscovered,2);
  assert.equal(p.plan.find(x=>x.id==='W7_FULL_FLUTTER_TEST')?.program,'flutter');
});
