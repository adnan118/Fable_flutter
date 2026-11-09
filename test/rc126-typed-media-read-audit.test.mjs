import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {auditMediaArchitecture} from '../tools/enforce-media-architecture-rc114.mjs';
import {checkLayerSource} from '../tools/enforce-feature-architecture-rc115.mjs';

const base='packages/features/fable_media/lib/src/';
const read=(p)=>readFileSync(p,'utf8');
const domain=read(base+'domain/media_read_models.dart');
const app=read(base+'application/read_media_metadata_use_case.dart');
const data=read(base+'data/fable_media_read_source.dart');
const legacy=read(base+'media_read_repository.dart');
const tests=read('packages/features/fable_media/test/media_read_typed_rc126_test.dart');
const barrel=read('packages/features/fable_media/lib/fable_media.dart');

test('RC126 new media read layers do not violate typed source graph',()=>{
  assert.deepEqual(auditMediaArchitecture(process.cwd()),[]);
  for(const [layer,source,path] of [
    ['domain',domain,base+'domain/media_read_models.dart'],
    ['application',app,base+'application/read_media_metadata_use_case.dart'],
    ['data',data,base+'data/fable_media_read_source.dart'],
  ]) {
    assert.deepEqual(checkLayerSource({featureId:'media',layer,source,file:path}),[]);
  }
  assert.ok(!domain.includes('dart:io'));
  assert.ok(!app.includes('package:fable_core'));
  assert.ok(!domain.includes('Map<String,dynamic>'));
});

test('RC126 only signed project GET operations and verified Fable routes can execute',()=>{
  for(const required of [
    "'media.client-contract'", "'media.get'",
    "'/media/client-contract'", "'/media/:id'",
    "runtime.method.toUpperCase() != 'GET'",
    "asset.method.toUpperCase() != 'GET'",
    "!runtime.requiresAuth", "!asset.requiresAuth",
    "!runtime.enforceAuth", "!asset.enforceAuth",
    'bindings.verify(catalog)',
  ]) assert.ok(data.includes(required),required);
  assert.ok(!legacy.includes("'media.metadata'"));
  assert.ok(!legacy.includes("'media.clientContract'"));
  assert.ok(!data.includes("'media.metadata'"));
  assert.ok(!data.includes("'media.clientContract'"));
  assert.ok(legacy.includes('MediaRuntimeCapabilities'));
  assert.ok(legacy.includes('MediaAssetMetadata'));
  assert.ok(!legacy.includes('Map<String,dynamic>'));
  assert.ok(legacy.includes('catalog == null ? null'));
  assert.ok(barrel.includes("domain/media_read_models.dart"));
  assert.ok(barrel.includes("data/fable_media_read_source.dart"));
});

test('RC126 typed Domain does not publish credential URLs or raw payloads',()=>{
  const active=domain.replace(/\/\*[\s\S]*?\*\//g,'')
      .replace(/^\s*\/\/.*$/gm,'');
  for(const forbidden of ['final Uri', 'final String url', 'signedUrl',
    'storageKey', 'X-Amz', 'grantToken', 'password', 'Map<String,dynamic>',
    'Response<dynamic>', 'BackendApiGateway', 'FableAuthGateway']) {
    assert.ok(!active.includes(forbidden),'unsafe Domain field '+forbidden);
  }
  assert.ok(domain.includes('enum MediaAssetAccessMode { protected }'));
  for(const safeguard of [
    "protection['enabled'] != true",
    "protection['forcePrivate'] != true",
    "protection['directPublicUrls'] != false",
    "protection['directDownload'] != false",
    "protection['requireAuthorizationGrant'] != true",
    "drm['queryTokensAllowed'] != false",
    "features['signedS3Downloads'] != false",
    "access['playbackEndpoint'] != '/media/$id/playback'",
  ]) assert.ok(data.includes(safeguard),safeguard);
  assert.ok(data.includes('MediaAssetAccessMode.protected'));
  assert.ok(data.includes("access['url'] != null"));
  assert.ok(data.includes('Media response asset identifier mismatch'));
  assert.ok(data.includes('!_isSessionCurrent() || _identityRevision() != revision'));
});

test('RC126 regressions cover identity, verified routes and malformed data',()=>{
  for(const marker of [
    'no guessed IDs', 'unknown enum and inconsistent assets',
    'identity switch while GET response', 'missing identity gate',
    'legacy reader remains source-compatible', 'Other Backend independent port',
    'never exposes signed URL',
  ]) assert.ok(tests.includes(marker),marker);
});
