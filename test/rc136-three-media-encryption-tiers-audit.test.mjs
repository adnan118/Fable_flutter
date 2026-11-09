import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const models=readFileSync(new URL('../packages/features/fable_media/lib/src/domain/media_read_models.dart',import.meta.url),'utf8');
const decoder=readFileSync(new URL('../packages/features/fable_media/lib/src/data/fable_media_read_source.dart',import.meta.url),'utf8');
test('RC136 public Flutter only describes server-authoritative media tiers',()=>{
  for(const s of ['enum MediaEncryptionTier { none, local, drm }','encryptionTierVerified','clientReceivesEncryptionKey => false'])assert.ok(models.includes(s),s);
  for(const s of ["protection['encryptionTier']","protection['encryption']","Untrusted media encryption tier contract","MediaEncryptionTier.local","MediaEncryptionTier.drm"])assert.ok(decoder.includes(s),s);
  assert.ok(!models.includes('MEDIA_LOCAL_ENCRYPTION_KEY_B64'));
  assert.ok(!decoder.includes('MEDIA_LOCAL_ENCRYPTION_KEY_B64'));
  assert.ok(!decoder.includes('createDecipheriv'));
});
