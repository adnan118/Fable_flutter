import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const domain = readFileSync('packages/features/fable_media/lib/src/domain/protected_player_port.dart', 'utf8');
const broker = readFileSync('packages/features/fable_media/lib/src/application/protected_player_session.dart', 'utf8');
const described = readFileSync('packages/features/fable_media/lib/src/domain/media_byte_chunk.dart', 'utf8');
const tests = readFileSync('packages/features/fable_media/test/protected_player_session_rc119_test.dart', 'utf8');

test('RC119 native player port excludes HTTP/Fable/Flutter credentials', () => {
  assert.match(domain, /abstract interface class ProtectedPlayerPlatformPort/);
  assert.match(domain, /ProtectedPlayerRangeReader/);
  assert.match(described, /DateTime get authorizationDeadline/);
  for (const leak of [
    'package:dio', 'package:fable_core', 'package:flutter',
    'accessToken', 'mediaToken', 'FableAuthGateway',
    'X-Fable-Media-Token', 'HttpClient'
  ]) {
    assert.ok(!domain.includes(leak), leak);
    assert.ok(!broker.includes(leak), leak);
  }
});

test('RC119 broker has bounded reads, cancels and native stop on revocation', () => {
  for (const witness of [
    'maxConcurrentReads', 'MediaByteRange.maxLength',
    '_source.cancelPendingReads()', 'source.invalidations.listen',
    'ProtectedPlayerPhase.revoked', '_platform.stop()', '_rangeEpoch',
    '_source.authorizationDeadline', 'ProtectedPlayerEndOfFile',
    'ProtectedPlayerReadRejected', 'await _platform.seek'
  ]) {
    assert.ok(broker.includes(witness), witness);
  }
});

test('RC119 simulations include delayed native lifecycle and security failures', () => {
  for (const witness of [
    'old native prepare cannot resurrect', 'account switch immediately',
    'EOF, duplicate request', 'seek cancels old ranges',
    '403/expiry stop native', 'async play completion after switch',
    'close source does not revoke server'
  ]) {
    assert.ok(tests.includes(witness), witness);
  }
});
