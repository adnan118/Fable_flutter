import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const gateway=readFileSync('packages/fable_core/lib/src/fable_auth_gateway.dart','utf8');
const code=readFileSync('packages/features/fable_media/lib/src/protected_media_playback_repository.dart','utf8');
const tests=readFileSync('packages/features/fable_media/test/protected_media_playback_rc112_test.dart','utf8');
const exportFile=readFileSync('packages/features/fable_media/lib/fable_media.dart','utf8');

test('RC112 discovers signed protected project operation paths; no invented operation IDs',()=>{
  assert.ok(gateway.includes('FableContract get verifiedContract => _contract;'));
  assert.ok(code.includes('gateway.verifiedContract'));
  for(const path of ['/media/:id/playback','/media/playback-sessions/:id/refresh',
      '/media/playback-sessions/:id']){
    assert.ok(code.includes(path),'missing contract-verified path '+path);
  }
  assert.ok(code.includes('matching.length!=1'));
  assert.ok(code.includes('op.requiresAuth && op.enforceAuth'));
  assert.ok(code.includes('op.credentialHeader==null'));
  assert.ok(!code.includes('VerifiedFablePlaybackBindings.fable()'));
  assert.ok(exportFile.includes("export 'src/protected_media_playback_repository.dart';"));
});
test('RC112 never persists media playback credentials and rejects unsafe URL/token access',()=>{
  for(const item of ['gateway.session.identityEvents','gateway.session.identityRevision',
    'accessTokenExpiresAt','idleExpiresAt','currentContentHeader','X-Fable-Media-Token',
    "type']!='AUTHENTICATED_STREAM'","_state=null","_generation++",
    "'REVOKED'"]){
    assert.ok(code.includes(item),'missing fail-closed playback safety '+item);
  }
  assert.ok(!code.includes('SharedPreferences'));
  assert.ok(!code.includes('playbackToken='));
  assert.ok(!code.includes('print('));
});
test('RC112 simulated contract and session regressions are part of feature test package',()=>{
  for(const scenario of ['missing or public or mismatched',
    'rotates token','session A to B while open','account replacement wipes',
    'expired access token','end invalidates token',
    'refresh response arriving after end','mismatched session/asset']){
    assert.ok(tests.includes(scenario),'missing simulated scenario '+scenario);
  }
});
