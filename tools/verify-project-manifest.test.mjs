import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {reviewManifestCli} from './verify-project-manifest.mjs';
const sample={schemaVersion:1,kind:'fable.project-generation-manifest',project:{id:'demo-app',displayName:'Demo App'},
 backend:{kind:'fable',adapter:'fable-contract',origin:'https://api.example',contractSha256:'a'.repeat(64),
 contractProjectId:'demo-app',capabilities:['users'],operationIds:['auth.login'],dpop:'required'},
 frontend:{client:'flutter',features:['auth'],locales:['ar'],platforms:['android']},
 source:{backendCommit:'a'.repeat(40),flutterCommit:'b'.repeat(40)},execution:{initiator:'developer',mode:'guided'}};
const fixture=()=>{const dir=mkdtempSync(join(tmpdir(),'fable-manifest-'));return{dir,save:(name,data)=>{const file=join(dir,name);writeFileSync(file,JSON.stringify(data));return file},cleanup:()=>rmSync(dir,{recursive:true,force:true})}};
test('01 read-only verifier never certifies unverified input',()=>{const f=fixture();try{let result;const status=reviewManifestCli(['--manifest',f.save('input.json',sample)],x=>result=JSON.parse(x));assert.equal(status,0);assert.equal(result.contractSignatureVerified,false);assert.equal(result.productionReady,false);assert.equal(result.status,'VALIDATED_INPUT_ONLY')}finally{f.cleanup()}});
test('02 developer and agent decision parity is deterministic',()=>{const f=fixture();try{let result;const status=reviewManifestCli(['--manifest',f.save('dev.json',sample),'--compare',f.save('agent.json',{...sample,execution:{initiator:'agent',mode:'headless'}})],x=>result=JSON.parse(x));assert.equal(status,0);assert.equal(result.comparison.sameDecisions,true)}finally{f.cleanup()}});
test('03 divergent decisions exit with code 2 not a false pass',()=>{const f=fixture();try{let result;const status=reviewManifestCli(['--manifest',f.save('a.json',sample),'--compare',f.save('b.json',{...sample,frontend:{...sample.frontend,features:[]}})],x=>result=JSON.parse(x));assert.equal(status,2);assert.equal(result.status,'DIFFERENT_DECISIONS')}finally{f.cleanup()}});
test('04 unknown flags and unsafe execution rejected',()=>assert.throws(()=>reviewManifestCli(['--apply','unsafe']),/CLI_OPTIONS_INVALID/));
test('05 invalid JSON never creates an approval',()=>{const f=fixture();try{const file=join(f.dir,'bad.json');writeFileSync(file,'{');assert.throws(()=>reviewManifestCli(['--manifest',file]),SyntaxError)}finally{f.cleanup()}});
