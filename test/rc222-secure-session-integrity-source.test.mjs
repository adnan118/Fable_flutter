import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const src=read('packages/fable_core/lib/src/fable_session.dart');
const native=read('packages/fable_core/test/rc222-secure-session-integrity_test.dart');
const runner=read('tools/fable-one-command.mjs');

const isolate=(start,end)=>{
 const at=src.indexOf(start),to=src.indexOf(end,at+1);
 assert.ok(at>0&&to>at,'RC222 source boundary '+start);
 return src.slice(at,to);
};
test('RC222 persistent credential marker is project-namespace-scoped',()=>{
 assert.match(src,/String get _integrityKey => '\$_prefix\.session\.integrity';/);
 assert.ok(src.includes("value:'updating'"));
 assert.ok(src.includes("value:'ready'"));
 assert.ok(src.includes("_unsafeSessionNamespaces"));
});
test('RC222 durable failure barrier blocks every committed credential read',()=>{
 const readBody=isolate('Future<String?> _readCommittedCredential(', 
   '/// Commit refreshed credentials');
 assert.match(readBody,/await _serializedWrite\(\(\) async/);
 assert.match(readBody,/if \(!await _credentialsReadable\(\)\) return;/);
 assert.match(readBody,/value=await _storage\.read\(key:key\)/);
});
test('RC222 original access+refresh reads cannot bypass serial integrity verification',()=>{
 assert.ok(!src.includes('return _storage.read(key:_accessKey);'));
 assert.ok(!src.includes('return _storage.read(key:_refreshKey);'));
 assert.ok(src.includes('get accessToken => _readCommittedCredential(_accessKey)'));
 assert.ok(src.includes('get refreshToken => _readCommittedCredential(_refreshKey)'));
});
test('RC222 refresh mutations commit integrity after both secure token writes',()=>{
 const fn=isolate('Future<bool> saveTokensIfIdentity(', 'Future<void> saveTokens(');
 assert.ok(fn.indexOf('await _startCredentialMutation()')<
    fn.indexOf('await _storage.write(key:_accessKey'));
 assert.ok(fn.indexOf('await _finishCredentialMutation()')>
    fn.indexOf('await _storage.write(key:_refreshKey'));
 assert.match(fn,/_invalidateAfterSecureStorageFailure\(\)/);
});
test('RC222 new identity epoch follows durable credential commit, never precedes it',()=>{
 const fn=isolate('Future<bool> replaceTokensIfIdentity(', 'Future<void> replaceTokens(');
 assert.ok(fn.indexOf('await _finishCredentialMutation()')<
   fn.indexOf('_advanceIdentity();'));
 assert.ok(fn.indexOf('_publishIdentity(true)')>
   fn.indexOf('await _finishCredentialMutation()'));
 assert.match(fn,/_invalidateAfterSecureStorageFailure\(\)/);
});
test('RC222 logout identity epoch advances only after all secure key deletes',()=>{
 const fn=isolate('Future<bool> clearSessionIfIdentity(', 'Future<void> clearSession()');
 assert.ok(fn.indexOf('await _storage.delete(key:_refreshKey)')<
   fn.indexOf('await _finishCredentialMutation()'));
 assert.ok(fn.indexOf('await _finishCredentialMutation()')<
   fn.indexOf('_advanceIdentity();'));
 assert.match(fn,/_invalidateAfterSecureStorageFailure\(\)/);
});
test('RC222 interrupted session state fails closed across device restarts',()=>{
 const fn=isolate('Future<bool> _credentialsReadable()', 'Future<void> _serializedWrite(');
 assert.match(fn,/_unsafeSessionNamespaces\.contains\(_prefix\)/);
 assert.match(fn,/state==null \|\| state=='ready'/);
 assert.match(native,/RC222 persisted interrupted marker fails closed after a simulated app restart/);
});
test('RC222 real fault-injection Flutter tests remain included in one pnpm command',()=>{
 assert.equal((native.match(/test\('/g)||[]).length,10);
 assert.ok(native.includes('class _ControlledStorage implements FlutterSecureStorage'));
 assert.ok(native.includes('rc222.logout.failure'));
 assert.ok(native.includes('rc222.recovery'));
 assert.ok(runner.includes('rc222-secure-session-integrity_test.dart'));
});
