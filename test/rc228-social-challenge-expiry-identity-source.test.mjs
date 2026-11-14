import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=(name)=>readFileSync(new URL('../'+name,import.meta.url),'utf8');
const code=read('packages/features/fable_social/lib/src/social_auth_repository.dart');
const dart=read('packages/features/fable_social/test/social_auth_repository_test.dart');
const runner=read('tools/fable-one-command.mjs');

function excerpt(start,end){
  const i=code.indexOf(start),j=code.indexOf(end,i+start.length);
  assert.ok(i>=0&&j>i,'source boundary '+start);
  return code.slice(i,j);
}
test('RC228 all social operation roles require authenticated policy enforcement',()=>{
  const bound=excerpt('factory FableSocialOperations._checked(', 'bool supports(String role)');
  assert.match(bound,/!op\.enforceAuth/);
  assert.match(bound,/op\.requiresAuth != _authorized\.contains\(binding\.key\)/);
  assert.match(bound,/op\.credentialHeader != null/);
});
test('RC228 social link refuses account switch while awaiting secure token read',()=>{
  const run=excerpt('Future<FableSocialAuthResult?> _run(', "if (payload['requiresTwoFactor'] == true)");
  assert.ok(run.includes('final token = await session.accessToken;'));
  assert.ok(run.includes('if (session.identityRevision != identity) return null;'));
  assert.ok(run.indexOf('if (session.identityRevision != identity) return null;') <
    run.indexOf("operations.require('challenge')"));
});
test('RC228 challenge clock starts before HTTP rather than after response',()=>{
  const run=excerpt('Future<FableSocialAuthResult?> _run(', "if (payload['requiresTwoFactor'] == true)");
  assert.ok(run.includes('Stopwatch()..start()'));
  assert.ok(run.indexOf('final challengeClock=Stopwatch()..start();') <
    run.indexOf("operations.require('challenge')"));
  assert.equal((run.match(/challengeClock\.elapsedMilliseconds >= challenge\.expiresInMs/g)||[]).length,2);
  assert.ok(!run.includes('final started = DateTime.now().toUtc();'));
});
test('RC228 expired challenge must not post credentials or link identities',()=>{
  const run=excerpt('Future<FableSocialAuthResult?> _run(', "if (payload['requiresTwoFactor'] == true)");
  assert.ok(run.indexOf("throw StateError('Social challenge expired')") <
    run.indexOf("operations.require(role)"));
  assert.ok(run.includes('if (credential.provider != provider || credential.nonce != challenge.nonce)'));
});
test('RC228 social credential source still commits only matching identity',()=>{
  assert.ok(code.includes('session.replaceTokensIfIdentity(expectedIdentity: identity'));
  assert.ok(code.includes('if (!saved) return null;'));
});
test('RC228 native social regressions include delay and link session races',()=>{
  assert.ok(dart.includes('a delayed challenge response cannot revive expired OAuth nonce'));
  assert.ok(dart.includes('account switch during secure token lookup cannot start social link'));
  assert.ok(dart.includes("FableSocialOperations.fable(contract(unenforced:true))"));
  assert.equal((dart.match(/test\('/g)||[]).length,10);
});
test('RC228 one existing pnpm command runs targeted social Dart suite',()=>{
  assert.ok(runner.includes('packages/features/fable_social/test/social_auth_repository_test.dart'));
});
