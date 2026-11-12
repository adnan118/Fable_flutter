import test from 'node:test';
import assert from 'node:assert/strict';
import { validateProjectGenerationManifest as validate, compareProjectGenerationManifests as compare, KNOWN_FLUTTER_FEATURES } from './project-generation-manifest.mjs';
const commits={backendCommit:'a'.repeat(40),flutterCommit:'b'.repeat(40)};
const spec=(kind='fable',initiator='developer')=>({schemaVersion:1,kind:'fable.project-generation-manifest',
  project:{id:'demo-project',displayName:'Demo Project'},
  backend:{kind,adapter:kind==='fable'?'fable-contract':'openapi',origin:'https://api.example',
    contractSha256:'c'.repeat(64),contractProjectId:kind==='fable'?'demo-project':null,
    capabilities:kind==='fable'?['users','auth']:[],operationIds:['auth.login','users.me'],
    dpop:kind==='fable'?'required':'forbidden'},
  frontend:{client:'flutter',features:['auth','profile'],locales:['ar','en'],platforms:['android','ios']},
  source:commits,execution:{initiator,mode:initiator==='developer'?'guided':'headless'}});
const fail=(val,msg)=>assert.throws(()=>validate(val),msg);
test('01 all seventeen stable Flutter families are unique',()=>{assert.equal(KNOWN_FLUTTER_FEATURES.length,17);assert.equal(new Set(KNOWN_FLUTTER_FEATURES).size,17)});
test('02 Fable DPoP required, input is not signed evidence',()=>{const r=validate(spec());assert.equal(r.manifest.backend.dpop,'required');assert.equal(r.trust.contractSignatureVerified,false);assert.equal(r.trust.productionReady,false)});
test('03 Other Backend no Fable DPoP',()=>assert.equal(validate(spec('other')).manifest.backend.dpop,'forbidden'));
test('04 guided developer and headless agent same decisions',()=>{const r=compare(spec(),spec('fable','agent'));assert.equal(r.sameDecisions,true);assert.equal(r.verifiedGeneratedProjects,false)});
test('05 changed selection changes hash',()=>{const a=spec(),b=spec();b.frontend.features=['profile'];assert.equal(compare(a,b).sameDecisions,false)});
test('06 ordering of selections is irrelevant',()=>{const a=spec(),b=spec();b.backend.capabilities.reverse();b.frontend.features.reverse();assert.equal(compare(a,b).sameDecisions,true)});
test('07 duplicate feature denied',()=>{const a=spec();a.frontend.features.push('auth');fail(a,/FLUTTER_FEATURES_DUPLICATE/)});
test('08 invented feature denied',()=>{const a=spec();a.frontend.features=['invented'];fail(a,/FLUTTER_FEATURES_UNKNOWN/)});
test('09 path-traversal project ID denied',()=>{const a=spec();a.project.id='../escape';fail(a,/PROJECT_ID_INVALID/)});
test('10 insecure or credential-bearing origin denied',()=>{for(const origin of ['http://api.example','https://api.example/path','https://api.example?token=abc','https://user:pass@api.example']){const a=spec();a.backend.origin=origin;fail(a,/BACKEND_ORIGIN/)}});
test('11 Fable cannot turn DPoP off',()=>{const a=spec();a.backend.dpop='forbidden';fail(a,/FABLE_BACKEND_POLICY/)});
test('12 Other Backend cannot import Fable DPoP',()=>{const a=spec('other');a.backend.dpop='required';fail(a,/OTHER_BACKEND_POLICY/)});
test('13 Other Backend cannot inherit Fable capabilities',()=>{const a=spec('other');a.backend.capabilities=['auth'];fail(a,/OTHER_BACKEND_POLICY/)});
test('14 external Auth needs declared contract operations',()=>{const a=spec('other');a.backend.operationIds=[];fail(a,/OTHER_AUTH_CONTRACT_OPERATIONS_REQUIRED/)});
test('15 mismatched Fable project pin denied',()=>{const a=spec();a.backend.contractProjectId='wrong';fail(a,/FABLE_BACKEND_POLICY/)});
test('16 missing contract hash or exact source pin denied',()=>{const a=spec();a.backend.contractSha256='aaa';fail(a,/CONTRACT_SHA256_INVALID/);const b=spec();b.source.flutterCommit='wrong';fail(b,/FLUTTER_COMMIT_INVALID/)});
test('17 secret-bearing fields denied',()=>{const a=spec();a.backend.secretKey='abc';fail(a,/CREDENTIAL_FIELD_FORBIDDEN/)});
test('18 unrecognized options denied',()=>{const a=spec();a.backend.securityLevel='weaker';fail(a,/BACKEND_UNKNOWN_FIELD/)});
test('19 wrong initiator/mode mapping denied',()=>{const a=spec();a.execution.mode='headless';fail(a,/EXECUTION_MODE_INVALID/)});
test('20 missing target platform denied',()=>{const a=spec();a.frontend.platforms=[];fail(a,/FRONTEND_TARGET_REQUIRED/)});
test('21 stable canonical hash',()=>{assert.deepEqual(validate(spec()),validate(spec()))});
test('22 all real approvals remain unavailable until verified externally',()=>{assert.deepEqual(validate(spec()).trust,{contractSignatureVerified:false,actualGeneratedProjectVerified:false,liveE2EVerified:false,productionReady:false})});
