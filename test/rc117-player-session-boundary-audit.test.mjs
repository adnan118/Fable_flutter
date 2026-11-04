import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const root='packages/features/fable_media/lib/src/';
const domain=readFileSync(root+'domain/media_session_bound_source.dart','utf8');
const useCase=readFileSync(root+'application/read_media_range_use_case.dart','utf8');
const data=readFileSync(root+'data/fable_media_byte_source.dart','utf8');
const ui=readFileSync(root+'presentation/media_range_controller.dart','utf8');
const repo=readFileSync(root+'protected_media_playback_repository.dart','utf8');
const tests=readFileSync('packages/features/fable_media/test/media_session_boundary_rc117_test.dart','utf8');

test('RC117 Domain session boundary exposes no Fable/Dio/HTTP/native or tokens',()=>{
  assert.match(domain,/abstract interface class SessionBoundMediaByteSource/);
  assert.match(domain,/Stream<MediaSessionInvalidation> get invalidations/);
  assert.match(domain,/cancelPendingReads/);
  for(const leak of ['package:dio','package:fable_core','HttpClient','FableAuthGateway',
      'accountId','accessToken','Authorization','X-Fable-Media-Token']){
    assert.ok(!domain.includes(leak),'Domain must not contain '+leak);
  }
});
test('RC117 end, account change, refresh and dispose publish revocation',()=>{
  for(const signal of ['accountChanged','credentialsRotated','playbackEnded','disposed']){
    assert.ok(repo.includes('ProtectedPlaybackInvalidation.'+signal),signal);
  }
  assert.match(repo,/StreamController<ProtectedPlaybackInvalidation>\.broadcast\(sync:true\)/);
  assert.match(repo,/bool isCurrentView\(/);
  assert.match(repo,/cancelReadsForView\(/);
});
test('RC117 Fable adapter blocks stale reads before and after network',()=>{
  // RC118's additive metadata port MUST still implement the RC117
  // session invalidation contract; this is not a relaxed security check.
  assert.match(data,/implements DescribedMediaByteSource/);
  const described=readFileSync(root+'domain/media_byte_chunk.dart','utf8');
  assert.match(described,/implements SessionBoundMediaByteSource/);
  assert.match(data,/Future<MediaByteChunk> readChunk/);
  assert.match(data,/if\(!isActive\)/);
  assert.match(data,/repository\.invalidations\.listen/);
  assert.match(data,/repository\.cancelReadsForView\(playback\)/);
  assert.match(data,/await _subscription\?\.cancel\(\)/);
});
test('RC117 presentation purges cached bytes on invalidation and cancels',()=>{
  assert.match(useCase,/Stream<MediaSessionInvalidation> get invalidations/);
  assert.match(useCase,/if\(!isSourceActive\)/);
  assert.match(ui,/_read\.invalidations\.listen/);
  assert.match(ui,/_read\.cancelPendingReads\(\)/);
  assert.match(ui,/unawaited\(_subscription\.cancel\(\)\)/);
  for(const scenario of ['account replacement synchronously purges',
      'late result cannot repopulate','credential rotation and server end',
      'reset and dispose cancel','source close emits a safe']){
    assert.ok(tests.includes(scenario),'missing '+scenario);
  }
});
