import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, statSync} from 'node:fs';

const dart = readFileSync('integration_test/rc122_protected_video_test.dart','utf8');
const flutter = readFileSync('packages/features/fable_media/lib/src/presentation/fable_native_protected_player.dart','utf8');
const ci = readFileSync('.github/workflows/rc122-codec-simulator.yml','utf8');
const runner = readFileSync('tools/rc122_codec_simulator_smoke.py','utf8');

test('RC122 tests original real MP4 through native decoder and bounded source', () => {
  assert.equal(statSync('assets/videos/rc122_blue_h264.mp4').size, 1569);
  for (const condition of ['rootBundle.load(', 'implements DescribedMediaByteSource',
      'FableNativeProtectedPlayerSurface(', 'FableNativePlayerEventKind.ready',
      'FableNativePlayerEventKind.ended', 'await session.play()',
      'rangeReadCount, greaterThanOrEqualTo(2)'])
    assert.ok(dart.includes(condition),condition);
  assert.ok(flutter.includes('widget.onNativeEvent?.call(event)'));
});

test('RC122 Xcode 27 integration smoke is mandatory and cannot fake ready', () => {
  assert.ok(ci.includes('runs-on: xcode-27'));
  assert.ok(ci.includes('tools/rc122_codec_simulator_smoke.py'));
  assert.ok(ci.includes('e477b0298e79f42fc73c3270c36a5b032579b713'));
  assert.ok(runner.includes('"flutter", "test", TARGET, "-d", udid'));
  assert.ok(runner.includes('timeout=1800'));
  assert.ok(!ci.includes('continue-on-error'));
});
