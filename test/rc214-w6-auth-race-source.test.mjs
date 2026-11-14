import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const gateway=read('packages/fable_core/lib/src/fable_auth_gateway.dart');
const screen=read('packages/features/fable_auth/lib/src/login_page.dart');
const dartGatewayTests=read('packages/fable_core/test/auth_gateway_identity_regression_test.dart');
const widgetTests=read('packages/features/fable_auth/test/mandatory_password_change_page_test.dart');

test('RC214 W6 late old logout requires successful local identity-bound clear and confirmed server revocation',()=>{
  const fn=gateway.slice(gateway.indexOf('Future<bool> logout() async'),
    gateway.indexOf('Future<bool> logout() async')+1300);
  assert.match(fn,/clearedThisIdentity=await session\.clearSessionIfIdentity\(identityAtStart\)/);
  assert.match(fn,/return clearedThisIdentity && revokedOnServer;/);
  assert.ok(!fn.includes('await session.clearSession();'));
});
test('RC214 W6 saved session verification releases busy state after another login takes over',()=>{
  const section=screen.slice(screen.indexOf('Future<void> _verifySavedSession()'),
    screen.indexOf('@override void dispose()'));
  assert.match(section,/if\(mounted\)setState\(\(\)=>_busy=false\)/);
  assert.match(section,/client\.session\.identityRevision!=revision/);
});
test('RC214 W6 logout UI never claims old signout if active new credentials remain',()=>{
  const section=screen.slice(screen.indexOf('Future<void> _logout()'),
    screen.indexOf('@override Widget build('));
  assert.match(section,/final activeToken=await client\.session\.accessToken/);
  assert.match(section,/activeToken!=null && activeToken\.isNotEmpty/);
  assert.match(section,/Session changed during sign-out/);
  assert.match(section,/_savedSessionAvailable=true/);
});
test('RC214 W6 delayed login rejection respects the originating session identity',()=>{
  const section=screen.slice(screen.indexOf('Future<void> _login()'),
    screen.indexOf('Future<void> _requestCode()'));
  assert.match(section,/final identityAtStart=client\.session\.identityRevision/);
  assert.match(section,/client\.session\.identityRevision==identityAtStart/);
  assert.match(section,/if \(mounted\) setState\(\(\) => _busy = false\)/);
});
test('RC214 W6 Dart tests include late successful old revocation and three Widget concurrency paths',()=>{
  assert.ok(dartGatewayTests.includes('RC214 old logout cannot report server sign-out success'));
  assert.ok(dartGatewayTests.includes("'revoked':true"));
  assert.ok(widgetTests.includes('RC214 stale saved-session verification unlocks'));
  assert.ok(widgetTests.includes('RC214 late old logout never claims sign-out'));
  assert.ok(widgetTests.includes('RC214 late rejected login must not display'));
  assert.ok(widgetTests.includes('Completer<void>()'));
});
test('RC214 W6 Fable-only Auth change does not remove DPoP/Auth or make false production claims',()=>{
  assert.ok(gateway.includes('resolveFableDpopProofSigner('));
  assert.ok(gateway.includes('adapter: FableTransportAdapter(catalog: contract)'));
  assert.ok(screen.includes("widget.contract.supports('auth.login')"));
});
