import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
const dir='packages/features/fable_media/lib/src/';
const upload=read(dir+'media_upload_repository.dart');
const metadata=read(dir+'media_read_repository.dart');
const playback=read(dir+'protected_media_playback_repository.dart');
const other=read(dir+'data/other_backend_protected_media_source.dart');
const local=read(dir+'data/fable_local_encrypted_buffered_uploader.dart');
const typed=read(dir+'data/fable_media_read_source.dart');

// The source gate checks actual committed Flutter code, not a synthetic implementation.
// It is NOT Flutter/Dart execution or mobile-device E2E acceptance.
test('RC176 upload source binds protected Fable routes, Other roles and local resume bytes',()=>{
 for(const v of ["'/media/uploads/prepare'","'/media/uploads/:id/chunk'",
  '!op.requiresAuth','!op.enforceAuth','MediaUploadBindings.other',
  'seven explicit mapped operation roles','File bytes changed; cannot resume',
  'NEVER persist the presigned URL'])assert.ok(upload.includes(v),v);
});
test('RC176 metadata source is inert without verified project and typed, not raw payload',()=>{
 for(const v of ['catalog == null ? null','verified project OperationCatalog',
  'MediaAssetMetadata'])assert.ok(metadata.includes(v),v);
 assert.equal(metadata.includes('Map<String,dynamic>'),false);
 for(const v of ['identityRevision','MediaAssetAccessMode.protected'])
   assert.ok(typed.includes(v),v);
});
test('RC176 playback source enforces exact routes, identity, cancellation and expiry',()=>{
 for(const v of ["'/media/:id/playback'",
   "'/media/playback-sessions/:id/refresh'",
   "'/media/playback-sessions/:id'",
   'gateway.session.identityEvents.listen','_state=null',
   '_cancelReads()','Protected playback session invalidated',
   '_future(view.expiresAt)','_future(view.accessTokenExpiresAt)'])
   assert.ok(playback.includes(v),v);
});
test('RC176 Other/LOCAL adapters never borrow Fable Auth or export AES keys',()=>{
 for(const forbidden of ['FableAuthGateway',"'media.upload'"])
   assert.equal(other.includes(forbidden),false,forbidden);
 for(const v of ['contractVerified','readVerifiedRange'])
   assert.ok(other.includes(v),v);
 for(const v of ['MediaEncryptionTier.local','encryptionTierVerified'])
   assert.ok(local.includes(v),v);
 assert.equal(local.includes('MEDIA_LOCAL_ENCRYPTION_KEY_B64'),false);
});
