import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const resolve=read('packages/fable_core/lib/src/fable_native_dpop_proof_signer.dart');
const transport=read('packages/fable_core/lib/src/fable_api.dart');
const auth=read('packages/fable_core/lib/src/fable_auth_gateway.dart');
const adapter=read('packages/fable_core/lib/src/backend_transport_adapter.dart');
const policy=read('packages/fable_core/lib/src/fable_contract.dart');
const android=read('android/app/src/main/kotlin/com/example/helloworld/FableDpopNativeBridge.kt');
const ios=read('ios/Runner/FableDpopNativeBridge.swift');
const parity=JSON.parse(read('docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json'));
const dpopNativeTests=read('packages/fable_core/test/rc188_fable_only_dpop_policy_test.dart');
test('01 exact 17 Flutter feature families remain live-unverified, despite source simulation acceptance',()=>{
 assert.equal(parity.features.length,17);assert.equal(new Set(parity.features.map(x=>x.id)).size,17);
 assert.ok(parity.features.every(x=>x.complete===false && x.liveE2EVerified===false));
});
test('02 automatic Fable DPoP default is enabled, never declared off',()=>{
 assert.match(resolve,/'FABLE_DPOP_NATIVE_ENABLED',[\s\S]*?defaultValue: true/);
 assert.doesNotMatch(resolve,/'FABLE_DPOP_NATIVE_ENABLED',[\s\S]*?defaultValue: false/);
});
test('03 Fable DPoP cannot attach to Other Backend, even with explicit injected signer',()=>{
 const other=resolve.slice(resolve.indexOf('if (catalog is! FableContract)'),resolve.indexOf('if (kIsWeb)'));
 assert.ok(other.includes("throw ArgumentError('Fable DPoP is forbidden for Other Backend')"));
 assert.ok(other.includes('return null;'));
 assert.ok(adapter.includes("'proxy-authorization', 'dpop'"));
});
test('04 Web remains separate and refuses native DPoP signer injection',()=>{
 const web=resolve.slice(resolve.indexOf('if (kIsWeb)'),resolve.indexOf('const enabled'));
 assert.ok(web.includes("throw ArgumentError('Native DPoP cannot be injected into Web')"));
 assert.ok(web.includes('return null;'));
});
test('05 release Fable DPoP cannot be disabled with a misconfigured build flag',()=>{
 assert.ok(resolve.includes("throw StateError('Fable DPoP cannot be disabled in a release build')"));
 assert.ok(resolve.includes('if (kReleaseMode)'));
});
test('06 Fable release pins actual nonfixture contract hash and HTTPS backend origin',()=>{
 for(const v of ["RegExp(r'^[a-f0-9]{64}$')","expectedHash == catalog.contractHash",
 "catalog.selectionMode == 'explicit'","catalog.isFeatureAvailable('auth')",
 "catalog.projectName != 'fable-test'","catalog.projectName != 'test-project'",
 "baseUri.origin == expectedOrigin","baseUri.scheme == 'https'"])assert.ok(resolve.includes(v),v);
});
test('07 missing Fable release source pins stop login; never downgrade silently to Bearer',()=>{
 assert.ok(resolve.includes("throw StateError('DPoP requires a verified non-fixture Fable project pin')"));
 assert.ok(resolve.includes("throw StateError('Fable release requires native hardware DPoP signing')"));
});
test('08 Flutter auth and API share exact signer selection',()=>{
 assert.ok(auth.includes('_dpopProofSigner = resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
 assert.ok(transport.includes('dpopProofSigner=resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
});
test('09 Android and iOS native keys are hardware scoped, no software fallback in Dart',()=>{
 assert.ok(android.includes('isInsideSecureHardware'));
 assert.ok(android.includes('AndroidKeyStore'));
 assert.ok(ios.includes('kSecAttrTokenIDSecureEnclave'));
 assert.ok(resolve.includes("throw StateError('Native hardware DPoP signing is unavailable')"));
});
test('10 server DPoP policy is checked freshly before each sign-in and refresh',()=>{
 assert.ok(transport.includes('_checkNativeDpopServerReady()'));
 assert.ok(transport.includes("'auth.login': '/auth/login'"));
 assert.ok(policy.includes('bool get requiresNativeDpop'));
 assert.ok(auth.includes("_dpopProofSigner != null && tokenType != 'DPoP'"));
});
test('11 Other Backend Dart tests include rejection of native and injected signers',()=>{
 assert.equal((dpopNativeTests.match(/test\('/g)||[]).length,4);
 assert.ok(dpopNativeTests.includes('Other Backend rejects an explicitly injected native signer'));
});
test('12 no test, source audit or simulated data may certify device or production readiness',()=>{
 assert.ok(parity.features.every(x=>x.complete===false&&x.liveE2EVerified===false));
 assert.equal(parity.stage6DevelopmentSimulation?.allFamiliesLiveE2EVerified,false);
});
