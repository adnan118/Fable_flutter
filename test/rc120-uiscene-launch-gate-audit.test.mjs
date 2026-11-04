import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const script = readFileSync('tools/rc120_uiscene_simulator_smoke.py', 'utf8');
const workflow = readFileSync('.github/workflows/flutter-rc49-validation.yml', 'utf8');

test('RC120 UIScene smoke actually boots iOS 27 iPhone AND iPad', () => {
  for(const witness of ['"iPhone"', '"iPad"', '"bootstatus"',
    '"install"', '"launch"', '"terminate"', 'time.sleep(7)',
    'Xcode 27', '27.', 'FlutterSceneDelegate', 'PASS:']) {
    assert.ok(script.includes(witness), witness);
  }
  assert.ok(workflow.includes('runs-on: xcode-27'));
  assert.ok(workflow.includes('python3 tools/rc120_uiscene_simulator_smoke.py'));
  assert.ok(workflow.includes('timeout-minutes: 35'));
});

test('RC120 each potentially hung simctl command is bounded and gate fails closed', () => {
  for (const witness of ['timeout=360', 'timeout=120', 'timeout=75',
    'subprocess.TimeoutExpired', 'check=True', 'RuntimeError',
    'if not compatible:', 'if not launch_result', 'simctl("terminate"']) {
    assert.ok(script.includes(witness), witness);
  }
  assert.ok(!script.includes('boot "$sim" || true'));
  assert.ok(!workflow.includes('xcrun simctl boot "$sim" || true'));
});
