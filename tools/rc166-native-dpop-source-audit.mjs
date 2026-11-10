import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve, join} from 'node:path';

/** Source-only guard: no Actions, SDK, credentials, emulator or network. */
const root=resolve(import.meta.dirname,'..');
const read=p=>readFileSync(join(root,p),'utf8');
const android=read('android/app/src/main/kotlin/com/example/helloworld/FableDpopNativeBridge.kt');
const activity=read('android/app/src/main/kotlin/com/example/helloworld/MainActivity.kt');
const ios=read('ios/Runner/FableDpopNativeBridge.swift');
const delegate=read('ios/Runner/AppDelegate.swift');
const xcode=read('ios/Runner.xcodeproj/project.pbxproj');
const bridge=read('packages/fable_core/lib/src/fable_native_dpop_proof_signer.dart');
const core=read('packages/fable_core/lib/src/fable_api.dart');
const auth=read('packages/fable_core/lib/src/fable_auth_gateway.dart');

test('RC166 native channel names match on both platforms and Dart',()=>{
 for(const s of [android,ios,bridge])
   assert.ok(s.includes('fable/dpop_native_v1'));
});
test('RC166 Android generates only hardware-backed AndroidKeystore EC P-256',()=>{
 for(const value of ['AndroidKeyStore','ECGenParameterSpec("secp256r1")',
  'KeyProperties.DIGEST_SHA256','isInsideSecureHardware'])assert.ok(android.includes(value),value);
 assert.ok(!android.includes('getEncoded()'));
});
test('RC166 Android encodes JWS ES256 P1363 instead of DER',()=>{
 for(const v of ['SHA256withECDSA','derToP1363','KEY_ALGORITHM_EC',
  'UUID.randomUUID()','MessageDigest.getInstance("SHA-256")'])assert.ok(android.includes(v),v);
});
test('RC166 iOS requires Secure Enclave and no plaintext key fallback',()=>{
 for(const value of ['kSecAttrTokenIDSecureEnclave','.privateKeyUsage',
  'SecKeyCreateRandomKey','SecKeyCreateSignature',
  'ecdsaSignatureMessageX962SHA256'])assert.ok(ios.includes(value),value);
 assert.ok(!ios.includes('P256.Signing.PrivateKey('));
});
test('RC166 existing iOS keys require Secure Enclave token ID at lookup',()=>{
 assert.equal((ios.match(/kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave/g)||[]).length,2);
 assert.ok(ios.includes('private func keyQuery(origin: String)'));
});
test('RC166 iOS converts DER ECDSA to RFC7515 P1363',()=>{
 assert.ok(ios.includes('encodeP1363('));
 assert.ok(ios.includes('return Data(r + s)'));
 assert.ok(ios.includes('leading & 0x80 == 0'));
});
test('RC166 native keys are scoped to a specific Fable HTTPS origin',()=>{
 assert.ok(android.includes('private fun alias(origin: String)'));
 assert.ok(android.includes('getOrCreate(expectedOrigin)'));
 assert.ok(ios.includes('private func keyTag(for origin: String)'));
 assert.ok(ios.includes('obtainPrivateKey(origin: origin)'));
});
test('RC166 iOS Swift bridge is explicitly compiled into Runner',()=>{
 assert.equal((xcode.match(/FableDpopNativeBridge\.swift/g)||[]).length,6);
 assert.ok(xcode.includes('FableDpopNativeBridge.swift in Sources'));
 assert.ok(delegate.includes('FlutterImplicitEngineDelegate'));
 assert.ok(delegate.includes('FableDpopNativeBridge(messenger: registrar.messenger())'));
});
test('RC166 Android engine owns channel and disposes on teardown',()=>{
 assert.ok(activity.includes('FableDpopNativeBridge(flutterEngine.dartExecutor.binaryMessenger)'));
 assert.ok(activity.includes('nativeDpop?.dispose()'));
});
test('RC166 Dart pins HTTPS origin, method, access-token before signing',()=>{
 for(const v of ["uri.scheme != 'https'","htu.origin != _origin.origin",
  "htu.hasQuery || htu.hasFragment","accessToken.length < 32",
  "invokeMethod<String>('sign'"])assert.ok(bridge.includes(v),v);
});
test('RC166 centrally gates activation by non-fixture contract and origin pins',()=>{
 for(const v of ['FABLE_DPOP_NATIVE_ENABLED','FABLE_DPOP_BACKEND_CONTRACT_HASH',
  'FABLE_DPOP_BACKEND_ORIGIN', "catalog.isFeatureAvailable('auth')",
  'catalog.selectionMode', "baseUri.origin != expectedOrigin"])
   assert.ok(bridge.includes(v),v);
 assert.ok(core.includes('resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
 assert.ok(auth.includes('resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
});
test('RC166 identity and entity can change while hardware signs: abort pre-send',()=>{
 const signerAt=core.indexOf('await signer.signProof(');
 const sendAt=core.indexOf('final response = await _dio.request<dynamic>(',signerAt);
 assert.ok(signerAt>0&&sendAt>signerAt);
 const after=core.slice(signerAt,sendAt);
 assert.ok(after.includes('rejectChangedContext()'));
 assert.ok(after.includes('session.identityRevision != expectedIdentity'));
});
test('RC166 iOS app delegate strongly retains the weak-handler native bridge',()=>{
 assert.ok(delegate.includes('private var nativeDpopBridge: FableDpopNativeBridge?'));
 assert.ok(delegate.includes('nativeDpopBridge = FableDpopNativeBridge(messenger: registrar.messenger())'));
 assert.ok(!delegate.includes('_ = FableDpopNativeBridge(messenger:'));
});
test('RC166 Dart API is not duplicated or truncated after network retry block',()=>{
 assert.equal((core.match(/class FableApiClient extends UnifiedApiClient/g)||[]).length,1);
 assert.equal((core.match(/class FableApiException implements Exception/g)||[]).length,1);
 assert.equal((core.match(/class UnifiedApiClient implements BackendApiGateway/g)||[]).length,1);
 assert.ok(!core.includes(').hasMatch(proof)) {\\n'));
 assert.match(core.trimEnd(),/}\s*$/);
});
test('RC166 never uses GitHub Actions as acceptance evidence',()=>{
 assert.ok(!bridge.includes('GitHub Actions'));
});
