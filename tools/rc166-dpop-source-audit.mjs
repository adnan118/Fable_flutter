import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,join} from 'node:path';

/** RC166 standalone review. No Flutter SDK, npm, network or GitHub Actions. */
const root=resolve(import.meta.dirname,'..','packages','fable_core');
const read=p=>readFileSync(join(root,p),'utf8');
const a=read('lib/src/fable_api.dart');
const auth=read('lib/src/fable_auth_gateway.dart');
const transport=read('lib/src/backend_transport_adapter.dart');
const port=read('lib/src/fable_dpop_proof_signer.dart');
const exports=read('lib/fable_core.dart');
const unit=read('test/rc166_fable_dpop_transport_port_test.dart');

test('native-only signer interface is injected, no private-key export',()=>{
  assert.ok(port.includes('abstract interface class FableDpopProofSigner'));
  assert.ok(!port.includes('exportPrivateKey'));
  assert.ok(exports.includes("src/fable_dpop_proof_signer.dart"));
});
test('injecting signer on Other Backend is refused',()=>{
  assert.ok(a.includes('contract is! FableContract || this.adapter is! FableTransportAdapter'));
});
test('proof signing occurs INSIDE request retry loop',()=>{
  assert.ok(a.indexOf('final attemptHeaders =')>a.indexOf('for (var attempt = 0;'));
  assert.ok(a.indexOf('await signer.signProof(')>a.indexOf('final attemptHeaders ='));
});
test('signature is bound to HTTP method and bare origin+path',()=>{
  assert.ok(a.includes("Uri.parse('${_baseUri.origin}$endpoint')"));
  assert.ok(a.includes('method: op.method, htu: htu, accessToken: token'));
});
test('only verified public Auth session endpoints receive public proofs',()=>{
  for(const id of ['auth.login','auth.refresh','auth.2fa.login.complete',
    'auth.otp.login.complete','auth.social.google','auth.social.apple']){
    assert.ok(a.includes("'"+id+"'"),id);
  }
  assert.ok(a.includes("op.method == 'POST' && op.path == publicPath"));
  assert.ok(a.includes('!op.requiresAuth && op.enforceAuth && op.credentialHeader == null'));
});
test('per-retry attempts dispatch only freshly signed headers',()=>{
  assert.ok(a.includes("headers: attemptHeaders"));
  assert.ok(a.includes("attemptHeaders['DPoP'] = proof"));
});
test('DPoP scheme is used with a supplied native signer',()=>{
  assert.ok(a.includes("'DPoP $token'"));
  assert.ok(a.includes("'DPoP $fresh'"));
});
test('old bearer scheme is preserved without a signer',()=>{
  assert.ok(a.includes("'Bearer $token'"));
  assert.ok(a.includes("'Bearer $fresh'"));
});
test('prevent ambient and provider-driven DPoP injection',()=>{
  assert.ok(a.includes("'x-api-key', 'dpop'"));
  assert.ok(a.includes("'authorization','dpop','cookie'"));
  assert.ok(transport.includes("'proxy-authorization', 'dpop'"));
});
test('FableAuthGateway binds injected signer to entire session lifecycle',()=>{
  assert.ok(auth.includes('dpopProofSigner: _dpopProofSigner'));
  assert.ok(auth.includes('_dpopProofSigner = resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
});
test('saving a DPoP session without signer fails closed',()=>{
  assert.ok(auth.includes("_dpopProofSigner == null && tokenType == 'DPoP'"));
});
test('saving a bearer session with DPoP signer fails closed',()=>{
  assert.ok(auth.includes("_dpopProofSigner != null && tokenType != 'DPoP'"));
});
test('Dart tests cover seven transport scenarios without real keys',()=>{
  assert.equal((unit.match(/test\('/g)||[]).length,7);
  assert.ok(unit.includes('does not sign or expose a P-256 private key'));
});
