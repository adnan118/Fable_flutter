import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const resolver=read('packages/fable_core/lib/src/fable_native_dpop_proof_signer.dart');
const adapter=read('packages/fable_core/lib/src/backend_transport_adapter.dart');
const transport=read('packages/fable_core/lib/src/fable_api.dart');
const auth=read('packages/fable_core/lib/src/fable_auth_gateway.dart');
const nativeTest=read('packages/fable_core/test/rc188_fable_only_dpop_policy_test.dart');
test('RC188 DPoP enabled by default only after detecting a real Fable catalog',()=>{
 assert.match(resolver,/catalog is! FableContract/);
 assert.match(resolver,/FABLE_DPOP_NATIVE_ENABLED'[\s\S]*defaultValue: true/);
});
test('RC188 Other Backend gets null without signer, not auto-enrollment',()=>{
 const scope=resolver.slice(resolver.indexOf('FableDpopProofSigner? resolveFableDpopProofSigner('));
 const other=scope.slice(scope.indexOf('if (catalog is! FableContract)'),scope.indexOf('if (kIsWeb)'));
 assert.match(other,/return null;/);
 assert.match(other,/if \(explicitlyProvided != null\)/);
 assert.match(other,/throw ArgumentError\('Fable DPoP is forbidden for Other Backend'\)/);
});
test('RC188 Other Backend transport prohibits DPoP and Authorization smuggling',()=>{
 assert.ok(adapter.includes("'proxy-authorization', 'dpop'"));
 assert.ok(transport.includes('if (this.dpopProofSigner != null && (contract is! FableContract || this.adapter is! FableTransportAdapter))'));
});
test('RC188 Fable release never falls back to Bearer when disabled by build setting',()=>{
 const scope=resolver.slice(resolver.indexOf('FableDpopProofSigner? resolveFableDpopProofSigner('));
 assert.match(scope,/if \(!enabled\) \{[\s\S]*?if \(kReleaseMode\) \{[\s\S]*?throw StateError\('Fable DPoP cannot be disabled in a release build'\)/);
});
test('RC188 release Fable requires verified contract SHA and HTTPS origin',()=>{
 for(const token of ["RegExp(r'^[a-f0-9]{64}$')","expectedHash == catalog.contractHash",
  "catalog.selectionMode == 'explicit'","baseUri.origin == expectedOrigin","baseUri.scheme == 'https'"])
 assert.ok(resolver.includes(token),token);
});
test('RC188 unpinned real Fable release stops rather than using unsigned requests',()=>{
 assert.ok(resolver.includes("throw StateError('DPoP requires a verified non-fixture Fable project pin')"));
 assert.ok(resolver.includes("throw StateError('Fable release requires native hardware DPoP signing')"));
});
test('RC188 Other Backend independent Dart regressions are present',()=>{
 for(const expected of ['Other Backend NEVER auto-enables Fable DPoP',
 'Other Backend rejects even an explicit Fable DPoP signer',
 'Other Backend rejects an explicitly injected native signer',
 'external UnifiedApiClient never accepts a Fable proof signer'])
 assert.ok(nativeTest.includes(expected),expected);
});
test('RC188 Fable native signer is still hardware only with no software-key fallback',()=>{
 assert.ok(resolver.includes("throw StateError('Native hardware DPoP signing is unavailable')"));
 assert.ok(resolver.includes("MethodChannel('fable/dpop_native_v1')"));
});
test('RC188 Fable AuthGateway uses the same central signer resolver',()=>{
 assert.ok(auth.includes('_dpopProofSigner = resolveFableDpopProofSigner(baseUri,contract,dpopProofSigner)'));
});
