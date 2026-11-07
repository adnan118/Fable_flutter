import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fable/protected_player_v1');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> prepare(FableNativeProtectedPlayerPort port,
      ProtectedPlayerRangeReader reader) =>
      port.prepare(
        const ProtectedPlayerMetadata(
          totalLength: 100, mimeType: 'video/mp4', rangeEpoch: 0),
        reader);

  MethodCall event(int id, int lease, String kind, int epoch) =>
      MethodCall('playerEvent', <String, Object>{
        'viewId': id, 'leaseId': lease,
        'event': kind, 'rangeEpoch': epoch,
      });

  MethodCall read(int id, int lease, int epoch, int requestId) =>
      MethodCall('readRange', <String, Object>{
        'viewId': id, 'leaseId': lease, 'requestId': requestId,
        'start': 0, 'length': 10, 'rangeEpoch': epoch,
      });

  ProtectedPlayerBytes bytes() => ProtectedPlayerBytes(MediaByteChunk(
    start: 0, totalLength: 100, mimeType: 'video/mp4',
    bytes: Uint8List.fromList(List<int>.filled(10, 42))));

  test('RC124 playing/paused/seeked require exact live lease and epoch',
      () async {
    final port = FableNativeProtectedPlayerPort(711);
    await prepare(port, (_) async => bytes());
    final lease = port.leaseIdForTesting;
    final events = <FableNativePlayerEventKind>[];
    final sub = port.events.listen((e) => events.add(e.kind));

    await port.play();
    await port.pause();
    expect(events, isEmpty,
        reason: 'MethodChannel ACK is not proof of native playback');

    for (final kind in ['playing', 'paused']) {
      expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
        event(711, lease - 1, kind, 0)),
        containsPair('status', 'rejected'));
      expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
        event(711, lease, kind, 0)),
        containsPair('status', 'accepted'));
    }
    expect(events, [
      FableNativePlayerEventKind.playing,
      FableNativePlayerEventKind.paused,
    ]);

    await port.seek(const Duration(seconds: 3), 1);
    expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(711, lease, 'seeked', 0)),
      containsPair('status', 'rejected'));
    expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(711, lease, 'seeked', 1)),
      containsPair('status', 'accepted'));

    await port.stop();
    expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(711, lease, 'playing', 1)),
      containsPair('status', 'rejected'));
    await sub.cancel();
    await port.dispose();
  });

  test('RC124 pending read before seek cannot return bytes in new epoch',
      () async {
    final gate = Completer<ProtectedPlayerReadReply>();
    final port = FableNativeProtectedPlayerPort(712);
    var reads = 0;
    await prepare(port, (request) {
      reads++;
      return reads == 1 ? gate.future : Future.value(bytes());
    });
    final lease = port.leaseIdForTesting;
    final old = FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(712, lease, 0, 41));
    await port.seek(const Duration(seconds: 3), 1);
    gate.complete(bytes());
    expect(await old, containsPair('status', 'rejected'));
    expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(712, lease, 0, 42)),
      containsPair('status', 'rejected'));
    expect(reads, 1);
    expect(await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(712, lease, 1, 43)),
      containsPair('status', 'bytes'));
    expect(reads, 2);
    await port.dispose();
  });
}
