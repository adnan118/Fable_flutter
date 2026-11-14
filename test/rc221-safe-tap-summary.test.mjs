import test from 'node:test';
import assert from 'node:assert/strict';
import {
  summarizeNodeTap,localRunner,buildOneCommandPlan,evaluateOneCommandPlan,
} from '../tools/fable-one-command.mjs';

const tap=({tests=5,pass=5,fail=0,skip=0}={})=>
  ['TAP version 13',
    'ok 1 - simulated source test',
    '# tests '+tests,'# pass '+pass,'# fail '+fail,
    '# cancelled 0','# skipped '+skip,'# todo 0','# duration_ms 12.3',
  ].join('\n')+'\n';
const plan=()=>buildOneCommandPlan({
 root:'/tmp/flutter',backendRoot:'/tmp/backend/Fable-Backend-RC66',
 packageScripts:{'test:safe':'node --test test/safe.test.mjs'},
 exists:()=>true,safeTestRead:()=>'',
 gitTestDiscovery:root=>({files:['test/safe.test.mjs'],
   rejected:[],gitInventoryVerified:true}),
});

test('RC221 final TAP totals are numeric and never copy test names',()=>{
 const c=summarizeNodeTap(tap());
 assert.deepEqual(c,{total:5,passed:5,failed:0,skipped:0,
   source:'NODE_TAP_FINAL_SUMMARY'});
 assert.equal(JSON.stringify(c).includes('simulated source test'),false);
});
test('RC221 Windows CRLF TAP source summaries parse identically',()=>{
 const a=summarizeNodeTap(tap({tests:4,pass:3,skip:1}).replace(/\n/g,'\r\n'));
 assert.equal(a.total,4);
 assert.equal(a.skipped,1);
});

test('RC221 captures genuine reported test failure count without source logs',()=>{
 const c=summarizeNodeTap(tap({tests:5,pass:3,fail:2}));
 assert.equal(c.failed,2);
 assert.equal(c.passed,3);
});
test('RC221 preserves skipped tests separately from passed source assertions',()=>{
 const c=summarizeNodeTap(tap({tests:5,pass:4,skip:1}));
 assert.equal(c.total,5);
 assert.equal(c.skipped,1);
});
test('RC221 accepts last complete TAP footer, not earlier test comments',()=>{
 const c=summarizeNodeTap([
  '# tests 123','# pass 0','# fail 123','# skipped 0',
  tap({tests:9,pass:9}),
 ].join('\n'));
 assert.equal(c.total,9);
 assert.equal(c.failed,0);
});
test('RC221 incomplete or malformed footer cannot be treated as verified test totals',()=>{
 for(const raw of ['','ok 1\n','# tests 5\n# pass 5',
   '# tests 999999999\n# pass 1\n# fail 0\n# skipped 0\n',
   tap({tests:2,pass:2,fail:1})])
   assert.equal(summarizeNodeTap(raw),null);
});
test('RC221 a non-TAP command cannot inject raw stdout into its report',()=>{
 const r=localRunner({
   program:'node',args:['tools/synthetic-check.mjs'],
   root:'/tmp/flutter',timeoutMs:100,
 },{
   spawn:()=>({status:0,signal:null,error:null,
     stdout:'session=secret_refresh_token'}),
   platform:'linux',now:()=>500,
 });
 assert.equal(r.testCounts,undefined);
 assert.equal(JSON.stringify(r).includes('secret_refresh_token'),false);
});
test('RC221 Node runner keeps numeric results and discards private source logs',()=>{
 const r=localRunner({
   program:'node',args:['--test','test/example.test.mjs'],
   root:'/tmp/flutter',timeoutMs:100,
 },{
   spawn:()=>({status:0,signal:null,error:null,
     stdout:tap({tests:7,pass:6,skip:1})+
       '\nAuthorization: Bearer never-export-this'}),
   platform:'linux',now:()=>500,
 });
 assert.equal(r.testCounts?.total,7);
 assert.equal(r.testCounts?.skipped,1);
 assert.equal(JSON.stringify(r).includes('Bearer'),false);
});
test('RC221 failed TAP cannot be locally classified PASS even with forged exit 0',()=>{
 const p=plan();
 const r=evaluateOneCommandPlan(p,[{
   id:'NODE_ALL_EXISTING_TEST_SCRIPTS',exitCode:0,signal:null,error:null,
   testCounts:summarizeNodeTap(tap({tests:3,pass:2,fail:1})),
 }]);
 assert.equal(r.checks[0].state,'FAILED');
 assert.equal(r.checks[0].reason,'NODE_TEST_FAILURES_IN_TAP_REPORT');
 assert.equal(r.observedNodeTestCounts.failed,1);
});
test('RC221 report exposes independent private Backend numeric totals',()=>{
 const p=plan();
 const r=evaluateOneCommandPlan(p,[
  {id:'NODE_ALL_EXISTING_TEST_SCRIPTS',exitCode:0,signal:null,error:null,
   testCounts:summarizeNodeTap(tap({tests:5,pass:5}))},
  {id:'BACKEND_ALL_TRACKED_NODE_TESTS',exitCode:0,signal:null,error:null,
   testCounts:summarizeNodeTap(tap({tests:12,pass:11,skip:1}))},
 ]);
 assert.equal(r.observedNodeTestCounts.total,17);
 assert.equal(r.observedNodeTestCounts.passed,16);
 assert.equal(r.observedNodeTestCounts.skipped,1);
 assert.equal(r.observedNodeTestCounts.processGroupsWithTapSummary,2);
});
test('RC221 report stays NO_GO even if all local TAP assertions passed',()=>{
 const p=plan();
 const r=evaluateOneCommandPlan(p,[{
   id:'NODE_ALL_EXISTING_TEST_SCRIPTS',exitCode:0,signal:null,error:null,
   testCounts:summarizeNodeTap(tap({tests:15,pass:15})),
 }]);
 assert.equal(r.productionReady,false);
 assert.equal(r.releaseDecision,'NO_GO');
 assert.equal(r.realAndroidVerified,false);
 assert.equal(r.liveProviderE2EVerified===undefined||r.realProviderE2EVerified===false,true);
});
