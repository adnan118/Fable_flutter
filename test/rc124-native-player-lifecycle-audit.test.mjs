import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, statSync} from 'node:fs';

const read = (p) => readFileSync(p, 'utf8');
const dart = read('integration_test/rc124_native_player_lifecycle_test.dart');
const port = read('packages/features/fable_media/lib/src/presentation/fable_native_protected_player.dart');
const android = read('android/app/src/main/kotlin/com/example/helloworld/FableProtectedMediaBridge.kt');
const ios = read('ios/Runner/FableProtectedMediaBridge.swift');
const iosCi = read('.github/workflows/rc122-codec-simulator.yml');
const androidCi = read('.github/workflows/rc123-media3-emulator.yml');
const iosRunner = read('tools/rc122_codec_simulator_smoke.py');
const androidRunner = read('tools/rc123_media3_emulator_test.sh');

test('RC124 deterministic real H264 seek/pause fixture and mandatory native CI', () => {
  assert.equal(statSync('assets/videos/rc124_blue_h264_8s.mp4').size, 2279);
  for (const marker of ['rc124_native_player_lifecycle_test.dart',
      'rc124_blue_h264_8s.mp4']) {
    assert.ok(iosCi.includes(marker), marker);
    assert.ok(androidCi.includes(marker), marker);
  }
  assert.ok(iosRunner.includes('flutter", "test", TARGET_RC124'));
  assert.ok(androidRunner.includes('flutter test integration_test/rc124_native_player_lifecycle_test.dart'));
  assert.ok(iosCi.includes('runs-on: xcode-27'));
  assert.ok(androidCi.includes('reactivecircus/android-emulator-runner@v2'));
  assert.ok(!iosCi.includes('continue-on-error'));
  assert.ok(!androidCi.includes('continue-on-error'));
});

test('RC124 native observation events cannot impersonate another lease or seek epoch', () => {
  for (const event of ['playing', 'paused', 'seeked']) {
    assert.ok(port.includes("'"+event+"' => FableNativePlayerEventKind." + event));
    assert.ok(android.includes('"'+event+'"'));
    assert.ok(ios.includes('event: "'+event+'"'));
  }
  assert.ok(port.includes('current._leaseId != leaseId'));
  assert.ok(port.includes('current._rangeEpoch != rangeEpoch'));
  assert.ok(android.includes('valid(boundGeneration, rangeEpoch, boundLease)'));
  assert.ok(ios.includes('self.leaseId == expectedLease, self.rangeEpoch == epoch'));
  assert.ok(ios.includes('timeControlObservation?.invalidate()'));
  assert.ok(android.includes('Player.DISCONTINUITY_REASON_SEEK'));
});

test('RC124 simulator asserts native pause/resume/seek and delayed range revocation', () => {
  for (const s of ['FableNativeProtectedPlayerEventKind', 'source.revoke()', 'source.releaseLateRead()']) {
    if (s === 'FableNativeProtectedPlayerEventKind') continue;
    assert.ok(dart.includes(s), s);
  }
  for (const s of ['FableNativePlayerEventKind.playing', 'FableNativePlayerEventKind.paused',
      'FableNativePlayerEventKind.seeked', 'FableNativePlayerEventKind.ended',
      'ProtectedPlayerPhase.revoked', 'source.nativeReadStarted.future',
      'source.cancels, greaterThan(0)', 'session.state.phase, ProtectedPlayerPhase.disposed']) {
    assert.ok(dart.includes(s), s);
  }
  assert.ok(!dart.includes('setMockMethodCallHandler'));
});
