import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const root='packages/features/fable_media/';
test('RC137 Other Backend transport never imports Fable auth, operation IDs or URLs',()=>{
  const external=read(root+'lib/src/data/other_backend_protected_media_source.dart');
  for(const forbidden of ["package:fable_core","FableAuthGateway","FableProtectedMediaPlaybackRepository",
    "'/media/","'media.upload'","'Authorization'","'X-Fable-"]){
    assert.equal(external.includes(forbidden),false,forbidden);
  }
  for(const required of ["OtherBackendVerifiedMediaTransport","identityRevision",
    "contractVerified","licensedDrmVerified","readVerifiedRange",
    "MediaSessionInvalidation.resourceChanged"]){
    assert.ok(external.includes(required),required);
  }
});
test('RC137 Fable LOCAL buffered upload refuses unverified or unprotected contracts',()=>{
  const uploader=read(root+'lib/src/data/fable_local_encrypted_buffered_uploader.dart');
  for(const required of ["catalog.require('media.upload')","operation.path!='/media'",
    "MediaEncryptionTier.local","encryptionTierVerified",
    "capabilities.maxUploadBytes","MultipartFile.fromFile",
    "access['type']!='protected'","identityRevision"]){
    assert.ok(uploader.includes(required),required);
  }
  assert.equal(uploader.includes('MEDIA_LOCAL_ENCRYPTION_KEY_B64'),false);
});
test('RC137 backend selection remains explicit for Fable versus independent Other',()=>{
  const selected=read('packages/fable_core/lib/src/backend_selection.dart');
  assert.ok(selected.includes("kind=='fable'"));
  assert.ok(selected.includes("kind=='other'"));
  assert.ok(selected.includes("adapter=='openapi'"));
  assert.ok(selected.includes("adapter=='custom'"));
  const exports=read(root+'lib/fable_media.dart');
  assert.ok(exports.includes('other_backend_protected_media_source.dart'));
  assert.ok(exports.includes('fable_local_encrypted_buffered_uploader.dart'));
});
