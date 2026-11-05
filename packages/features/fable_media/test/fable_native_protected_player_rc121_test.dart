import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fable/protected_player_v1');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MediaByteChunk chunk(int at, int length) => MediaByteChunk(
    start: at, totalLength: 120, mimeType: 'video/mp4',
    bytes: Uint8List.fromList(List.filled(length, 12)));

  Future<void> prepare(FableNativeProtectedPlayerPort p,
      ProtectedPlayerRangeReader reader) =>
      p.prepare(const ProtectedPlayerMetadata(
        totalLength: 120, mimeType: 'video/mp4', rangeEpoch: 0),
        reader);

  MethodCall read(int id, int lease, {int requestId = 1, int epoch = 0}) =>
      MethodCall('readRange', <String, Object>{
        'viewId': id, 'leaseId': lease,
        'requestId': requestId, 'start': 0, 'length': 6,
        'rangeEpoch': epoch,
      });

  MethodCall event(int id, int lease, String name, {int epoch = 0}) =>
      MethodCall('playerEvent', <String, Object>{
        'viewId': id, 'leaseId': lease,
        'event': name, 'rangeEpoch': epoch,
      });

  test('RC121 old account lease is rejected after same PlatformView ID reuse',
      () async {
    final previous = FableNativeProtectedPlayerPort(601);
    await prepare(previous, (request) async =>
        ProtectedPlayerBytes(chunk(request.start, request.length)));
    final old = previous.leaseIdForTesting;
    final oldPrepared = calls.first.arguments as Map;
    expect(oldPrepared['leaseId'], old);
    expect(oldPrepared.keys, isNot(contains('authorization')));
    expect(oldPrepared.keys, isNot(contains('url')));
    await previous.dispose();

    var newReads = 0;
    final current = FableNativeProtectedPlayerPort(601);
    await prepare(current, (request) async {
      newReads++;
      return ProtectedPlayerBytes(chunk(request.start, request.length));
    });
    expect(current.leaseIdForTesting, isNot(old));
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(601, old))) as Map, containsPair('status', 'rejected'));
    expect(newReads, 0);
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(601, current.leaseIdForTesting))) as Map,
      containsPair('status', 'bytes'));
    expect(newReads, 1);
    await current.dispose();
  });

  test('RC121 late old-source reply cannot escape after stop', () async {
    final port = FableNativeProtectedPlayerPort(602);
    final pending = Completer<ProtectedPlayerReadReply>();
    await prepare(port, (_) => pending.future);
    final request = FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      read(602, port.leaseIdForTesting));
    await port.stop();
    pending.complete(ProtectedPlayerBytes(chunk(0, 6)));
    expect((await request) as Map, containsPair('status', 'rejected'));
    await port.dispose();
  });

  test('RC121 ready/ended/decoder error signals are lease and epoch fenced',
      () async {
    final port = FableNativeProtectedPlayerPort(603);
    await prepare(port, (request) async =>
        ProtectedPlayerBytes(chunk(request.start, request.length)));
    final received = <FableNativePlayerEventKind>[];
    final subscription = port.events.listen((e) => received.add(e.kind));
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(603, port.leaseIdForTesting - 1, 'failed'))) as Map,
      containsPair('status', 'rejected'));
    expect(received, isEmpty);
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(603, port.leaseIdForTesting, 'ready'))) as Map,
      containsPair('status', 'accepted'));
    await port.seek(const Duration(seconds: 3), 1);
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(603, port.leaseIdForTesting, 'failed', epoch: 0))) as Map,
      containsPair('status', 'rejected'));
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(603, port.leaseIdForTesting, 'failed', epoch: 1))) as Map,
      containsPair('status', 'accepted'));
    expect(received, [
      FableNativePlayerEventKind.ready,
      FableNativePlayerEventKind.failed,
    ]);
    await port.stop();
    expect((await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      event(603, port.leaseIdForTesting, 'ended', epoch: 1))) as Map,
      containsPair('status', 'rejected'));
    await subscription.cancel();
    await port.dispose();
  });
}
