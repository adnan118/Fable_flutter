import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const dart = readFileSync(
  'packages/features/fable_media/lib/src/presentation/fable_native_protected_player.dart','utf8');
const session = readFileSync(
  'packages/features/fable_media/lib/src/application/protected_player_session.dart','utf8');
const android = readFileSync(
  'android/app/src/main/kotlin/com/example/helloworld/FableProtectedMediaBridge.kt','utf8');
const ios = readFileSync('ios/Runner/FableProtectedMediaBridge.swift','utf8');

test('RC121 native media range and all commands use a nonsecret lease', () => {
  for(const [source, guards] of [
    [dart, ["'_leaseId'"]], // special-case below; private variable is not a string literal
    [android, ['val requestedLease', 'surface.leaseId != requestedLease',
      '"leaseId" to leaseId', 'valid(generation, epoch, leaseId)']],
    [ios, ['requestedLease == surface.leaseId', '"leaseId": leaseId',
      'self.bridge.read(id: self.viewId, leaseId: self.leaseId']]
  ]) {
    for (const guard of guards) {
      if(guard === "'_leaseId'") continue;
      assert.ok(source.includes(guard), guard);
    }
  }
  assert.ok(dart.includes("port._leaseId != leaseId"));
  assert.ok(dart.includes("'leaseId': _leaseId"));
  assert.ok(dart.includes("port._rangeEpoch != epoch"));
  assert.ok(dart.includes("port._generation != generation"));
  for (const source of [dart, android, ios]) {
    assert.ok(!source.includes('Authorization: Bearer'));
    assert.ok(!source.includes('X-Fable-Media-Token'));
  }
});

test('RC121 decode errors are asynchronously delivered and revoke the byte broker', () => {
  for(const required of ['onPlayerError(error: PlaybackException)',
    'Player.STATE_READY', 'Player.STATE_ENDED',
    'bridge.notifyRenderer(viewId, boundLease, rangeEpoch, "failed")'])
    assert.ok(android.includes(required),required);
  for(const required of ['item.observe(\\.status', 'case .failed:',
     'AVPlayerItem.didPlayToEndTimeNotification', 'notifyRenderer',
     'statusObservation?.invalidate()'])
    assert.ok(ios.includes(required),required);
  for(const required of ["call.method == 'playerEvent'",
    'FableNativePlayerEventKind.failed','session.reportRendererFailure()',
    "current._events.add(FableNativePlayerEvent(kind, rangeEpoch))"])
    assert.ok(dart.includes(required),required);
  assert.ok(session.includes('void reportRendererFailure()'));
  assert.ok(session.includes('_fail(MediaReadFailureKind.unsupported)'));
});
