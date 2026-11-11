import test from 'node:test';
import assert from 'node:assert/strict';
import {FAMILIES,evaluateStage6Source} from '../tools/rc174-stage6-source-preflight.mjs';
const hash='a'.repeat(64);
const binding=(overrides={})=>({ok:true,backendKind:'fable',fixture:true,projectBound:false,
  contractHash:hash,selectedFeatureCount:17,...overrides});
const manifest=(overrides={})=>({features:[...FAMILIES],capabilities:[...FAMILIES],
  backendContractHash:null,...overrides});
const master=(overrides={})=>({kind:'fable.flutter-feature-parity-master',
  features:FAMILIES.map(id=>({id,complete:false,liveE2EVerified:false,
    gaps:['Needs real E2E'],otherBackendContract:['Independent mapping required']})),...overrides});
const check=(overrides={})=>evaluateStage6Source({mode:'source',binding:binding(),
  manifest:manifest(),master:master(),dpopTransportPassed:true,dpopNativePassed:true,
  ...overrides});
test('RC174 17-family fixture passes SOURCE preflight only, never Stage6 or production',()=>{
 const r=check();assert.equal(r.sourcePreflightPassed,true);
 assert.equal(r.realProjectBound,false);assert.equal(r.stage6Complete,false);
 assert.equal(r.authenticatedBackendE2E,false);assert.equal(r.productionReady,false);
 assert.equal(r.androidExecuted,false);assert.equal(r.iosExecuted,false);
});
test('RC174 real Fable project cannot pass without independent exact hash and non-fixture binding',()=>{
 let r=check({mode:'project'});
 assert.equal(r.sourcePreflightPassed,false);
 assert.ok(r.blockers.includes('REAL_FABLE_PROJECT_CONTRACT_PIN_REQUIRED'));
 r=check({mode:'project',binding:binding({fixture:false,projectBound:true}),
  manifest:manifest({backendContractHash:hash})});
 assert.equal(r.sourcePreflightPassed,true);assert.equal(r.realProjectBound,true);
 assert.equal(r.stage6Complete,false);assert.equal(r.productionReady,false);
});
test('RC174 a claimed complete or live E2E feature with no proof fails closed',()=>{
 const m=master();m.features[0].liveE2EVerified=true;
 assert.ok(check({master:m}).blockers.includes('UNVERIFIED_FEATURE_MARKED_COMPLETE'));
});
test('RC174 missing, unknown, duplicate, or altered feature manifest fails',()=>{
 const unknown=manifest();unknown.features[0]='new_invented';
 assert.ok(check({manifest:unknown}).blockers.includes('FEATURE_SELECTION_INVALID'));
 const duplicate=manifest();duplicate.features[1]=duplicate.features[0];
 assert.ok(check({manifest:duplicate}).blockers.includes('FEATURE_SELECTION_INVALID'));
 const short=manifest();short.features.pop();short.capabilities.pop();
 assert.ok(check({manifest:short}).blockers.includes('FEATURE_SELECTION_BINDING_MISMATCH'));
 const m=master();m.features.pop();
 assert.ok(check({master:m}).blockers.includes('FEATURE_PARITY_REGISTRY_INVALID'));
});
test('RC174 hardware/Dart DPoP source audits must execute and pass',()=>{
 assert.ok(check({dpopNativePassed:false}).blockers.includes('DPOP_NATIVE_SOURCE_AUDIT_NOT_PASSED'));
 assert.ok(check({dpopTransportPassed:false}).blockers.includes('DPOP_DART_SOURCE_AUDIT_NOT_PASSED'));
});
test('RC174 Other Backend cannot inherit Fable DPoP or claim independent project approval',()=>{
 const other=binding({backendKind:'other',contractHash:null,fixture:false});
 const src=check({binding:other});
 assert.equal(src.sourcePreflightPassed,true);assert.equal(src.realProjectBound,false);
 const real=check({mode:'project',binding:other});
 assert.ok(real.blockers.includes('OTHER_BACKEND_REQUIRES_INDEPENDENT_PROJECT_ACCEPTANCE'));
 const stolen=check({binding:other,manifest:manifest({backendContractHash:hash})});
 assert.ok(stolen.blockers.includes('OTHER_BACKEND_CANNOT_BORROW_FABLE_HASH'));
});
test('RC174 source verifier failure or missing evidence never becomes PASS',()=>{
 assert.ok(check({binding:binding({ok:false})}).blockers.includes('PROJECT_CONTRACT_SOURCE_CHECK_FAILED'));
 assert.ok(check({master:null}).blockers.includes('FEATURE_PARITY_REGISTRY_INVALID'));
});
