import test from 'node:test';
import assert from 'node:assert/strict';
import {
  RELEASE_PHASES,buildLocalAcceptancePlan,evaluateLocalAcceptance,
  checkLocalGitSource,runLocalAcceptance,
} from '../tools/w7-w8-local-acceptance.mjs';
import {parseLocalCloseoutArgs} from '../tools/run-w7-w8-local-acceptance.mjs';

const sha='a'.repeat(40),shaOther='b'.repeat(40),hash='a'.repeat(64);
const opts={
  flutterRoot:'.',backendRoot:'../Fable/Fable-Backend-RC66',
  expectedBackendSha:sha,expectedFlutterSha:shaOther,
};
const inventory={
 kind:'fable.final-closure-audit',
 counts:{families:17,sourceGapItems:60,crossCuttingItems:10,
  wizardScenarios:12,outstanding:82},
 blockers:[
  ...Array.from({length:60},(_,i)=>({id:'GAP-'+i,gate:'W6'})),
  ...Array.from({length:12},(_,i)=>({id:'WIZ-'+i,gate:'W4'})),
  ...Array.from({length:10},(_,i)=>({id:'CROSS-'+i,gate:'W7'})),
 ],
};
function checked(plan,runs=[],checkout={backendVerified:true,flutterVerified:true}){
 return evaluateLocalAcceptance(plan,{inventory,checkout,runs});
}
const passedRuns=plan=>plan.steps.map(s=>({id:s.id,exitCode:0,
  signal:null,error:null,durationMs:1}));

test('RC216 plan includes W0-W8, real generated Backend and all downstream source checks',()=>{
 assert.equal(RELEASE_PHASES.length,9);
 const p=buildLocalAcceptancePlan(opts);
 assert.deepEqual(p.steps.map(s=>s.id),[
  'W1_W2_REAL_GENERATION','W3_REAL_EXPORT_FLUTTER_IMPORT',
  'W4_TWELVE_REAL_WIZARD_PROJECTS','W5_COMPLETE_SELECTED_SOURCE_CHAIN',
  'W6_SELECTED_FAMILY_SOURCE_REGRESSIONS','W6_AUTH_NOTIFICATIONS_DART_WIDGET',
  'W7_FLUTTER_ANALYZE','W7_FLUTTER_TEST',
 ]);
 assert.deepEqual(p.steps[0].args,['tools/fable-w1-w2-one-shot.mjs','--full','--json']);
 assert.ok(p.steps.some(s=>s.additionalGate==='W2'));
});
test('RC216 no source pin or empty project evidence can be marked PASS',()=>{
 const p=buildLocalAcceptancePlan();
 const r=checked(p,passedRuns(p),{backendVerified:false,flutterVerified:false});
 assert.equal(r.releaseDecision,'NO_GO');
 assert.equal(r.sourceChecks.every(s=>s.state==='BLOCKED'),true);
 assert.equal(r.sourcePins.verifiedFlutter,false);
});
test('RC216 missing 3 Fable profiles blocks W4 despite fake successful runner results',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const r=checked(p,passedRuns(p));
 assert.equal(r.sourceChecks.find(s=>s.gate==='W4').state,'BLOCKED');
 assert.equal(r.sourceChecks.find(s=>s.gate==='W5').state,'BLOCKED');
});
test('RC216 rejected source origin invalidates Backend and Flutter source checks',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const r=checked(p,passedRuns(p),{backendVerified:false,flutterVerified:true});
 assert.equal(r.sourceChecks.find(s=>s.gate==='W1').state,'BLOCKED');
 assert.equal(r.sourceChecks.find(s=>s.gate==='W3').state,'BLOCKED');
 assert.equal(r.sourceChecks.find(s=>s.gate==='W4').state,'BLOCKED');
 assert.equal(r.sourceChecks.find(s=>s.gate==='W5').state,'BLOCKED');
});
test('RC216 source-only checks cannot become Android/iOS or provider proof',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const r=checked(p,passedRuns(p));
 assert.equal(r.sourceChecks.find(s=>s.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS')
  .state,'SOURCE_CHECK_PASS');
 assert.equal(r.actualAndroidDeviceVerified,false);
 assert.equal(r.actualIosDeviceVerified,false);
 assert.equal(r.liveProviderE2EVerified,false);
 assert.equal(r.independentProductionApproval,false);
 assert.equal(r.releaseDecision,'NO_GO');
});
test('RC216 W6 native tests require explicit opt-in and toolchain',()=>{
 const p=buildLocalAcceptancePlan({...opts,withFlutterToolchain:false});
 assert.ok(p.steps.filter(s=>s.program==='flutter').every(s=>s.requires));
 const native=buildLocalAcceptancePlan({...opts,withFlutterToolchain:true});
 assert.ok(native.steps.filter(s=>s.program==='flutter').every(s=>!s.requires));
 const r=checked(native,passedRuns(native));
 assert.equal(r.sourceChecks.find(s=>s.id==='W7_FLUTTER_ANALYZE').state,'LOCAL_TEST_PASS');
 assert.equal(r.actualAndroidDeviceVerified,false);
 assert.equal(r.productionReady,false);
});
test('RC216 fails closed on failed exit, timeout/signal and missing test invocation',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const good=passedRuns(p);
 const failed=checked(p,good.map(x=>x.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS'?
  {...x,exitCode:7}:x));
 assert.equal(failed.sourceChecks.find(s=>s.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS')
  .state,'FAILED');
 const empty=checked(p,[]);
 assert.equal(empty.sourceChecks.find(s=>s.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS')
  .state,'NOT_RUN');
 const signal=checked(p,good.map(x=>x.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS'?
  {...x,signal:'SIGKILL'}:x));
 assert.equal(signal.sourceChecks.find(s=>s.id==='W6_SELECTED_FAMILY_SOURCE_REGRESSIONS')
  .state,'FAILED');
});
test('RC216 never approves even when 82 items are marked externally accepted',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const zero={...inventory,counts:{...inventory.counts,outstanding:0},blockers:[]};
 const r=evaluateLocalAcceptance(p,{inventory:zero,
  checkout:{backendVerified:true,flutterVerified:true},runs:passedRuns(p),
  readinessEvidence:{selfAssertedApproved:true}});
 assert.equal(r.baseline.outstanding,0);
 assert.equal(r.providedReadinessEvidenceReviewed,false);
 assert.equal(r.productionReady,false);
 assert.equal(r.releaseDecision,'NO_GO');
});
test('RC216 baseline counts current W0 register including its 82 unsatisfied items',()=>{
 const p=buildLocalAcceptancePlan(opts);
 const r=checked(p);
 assert.equal(r.baseline.verified,true);
 assert.equal(r.baseline.outstanding,82);
 assert.equal(r.baseline.issuesByGate.W6,60);
 assert.equal(r.baseline.issuesByGate.W4,12);
});
test('RC216 refuses malformed checkout hashes and incomplete profile pins',()=>{
 assert.throws(()=>parseLocalCloseoutArgs(['--expected-backend-sha','abc']),/40-char/);
 assert.throws(()=>parseLocalCloseoutArgs(['--project-id','X']),/together/);
 assert.throws(()=>parseLocalCloseoutArgs(['--fable-minimal-export','/tmp/export']),/Profile minimal/);
 assert.throws(()=>parseLocalCloseoutArgs(['--unknown']),/Unknown/);
});
test('RC216 plans private source paths correctly for nested Backend checkout',()=>{
 const p=buildLocalAcceptancePlan(opts);
 assert.ok(p.backendRoot.endsWith('Fable-Backend-RC66'));
 assert.ok(p.backendCheckoutRoot.endsWith('Fable'));
 const withW3=buildLocalAcceptancePlan({...opts,backendExportRoot:'../real-contract'});
 assert.ok(withW3.steps[1].args.includes(p.backendCheckoutRoot));
});
test('RC216 no claimed real Git identity without an actual on-disk checkout',()=>{
 assert.equal(checkLocalGitSource('/definitely/not-a-real-repository',sha,'backend'),false);
 assert.equal(checkLocalGitSource('.', 'invalid','flutter'),false);
});
test('RC216 mock runner status never bypasses independent origin verification',()=>{
 const plan=buildLocalAcceptancePlan(opts);
 const called=[];
 const r=runLocalAcceptance(plan,{gitChecker:()=>false,runner:s=>{
  called.push(s.id);return {exitCode:0,signal:null,error:null,durationMs:1};
 }});
 assert.equal(called.length,0);
 assert.equal(r.sourceChecks.every(x=>x.state==='BLOCKED'),true);
 assert.equal(r.releaseDecision,'NO_GO');
});
