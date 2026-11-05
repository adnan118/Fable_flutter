import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, statSync} from 'node:fs';

const ci = readFileSync('.github/workflows/rc123-media3-emulator.yml', 'utf8');
const testSource = readFileSync('integration_test/rc122_protected_video_test.dart', 'utf8');
const android = readFileSync('android/app/src/main/kotlin/com/example/helloworld/FableProtectedMediaBridge.kt', 'utf8');

test('RC123 emulator gate uses hardware-accelerated Android and real Media3 decoder', () => {
  for(const marker of ['reactivecircus/android-emulator-runner@v2',
      'api-level: 35', 'arch: x86_64', 'test -e /dev/kvm',
      'flutter test integration_test/rc122_protected_video_test.dart -d emulator-5554',
      'git hash-object assets/videos/rc122_blue_h264.mp4',
      'e477b0298e79f42fc73c3270c36a5b032579b713']) {
    assert.ok(ci.includes(marker),marker);
  }
  assert.ok(!ci.includes('android-actions/setup-android@v3'),
    'Do not install obsolete sdkmanager tools package on Ubuntu 24.04');
  assert.ok(ci.includes('sdkmanager --version'));
  assert.equal(statSync('assets/videos/rc122_blue_h264.mp4').size, 1569);
});

test('RC123 never confuses build or method-channel ack with decoded playback', () => {
  for (const marker of ['FableNativePlayerEventKind.ready', 'FableNativePlayerEventKind.ended',
      'await session.play()', 'rangeReadCount, greaterThanOrEqualTo(2)']) {
    assert.ok(testSource.includes(marker),marker);
  }
  assert.ok(android.includes('onPlaybackStateChanged'));
  assert.ok(android.includes('Player.STATE_READY'));
  assert.ok(android.includes('Player.STATE_ENDED'));
  assert.ok(android.includes('FableProtectedRangeDataSource'));
  assert.ok(!ci.includes('continue-on-error'));
});
