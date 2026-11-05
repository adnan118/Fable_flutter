import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fable/protected_player_v1');
  final commands = <String>[];

  setUp(() {
    commands.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MediaByteChunk chunk(int start, int size) => MediaByteChunk(
    start: start, totalLength: 100, mimeType: 'video/mp4',
    bytes: Uint8List.fromList(List.filled(size, 7)),
  );

  test('RC120 native port forwards typed metadata and never a token or URL',
      () async {
    final port = FableNativeProtectedPlayerPort(24);
    await port.prepare(
      const ProtectedPlayerMetadata(
        totalLength: 100, mimeType: 'video/mp4', rangeEpoch: 0),
      (request) async => ProtectedPlayerBytes(
        chunk(request.start, request.length)),
    );
    final rawRead = await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
      const MethodCall('readRange', <String, Object>{
        'viewId': 24, 'requestId': 1, 'start': 5, 'length': 4,
        'rangeEpoch': 0,
      }),
    );
    final read = rawRead as Map;
    expect(read['status'], 'bytes');
    expect(read['bytes'], [7, 7, 7, 7]);
    expect(read['start'], 5);
    expect(read.keys, isNot(contains('url')));
    expect(read.keys, isNot(contains('token')));
    await port.play();
    await port.pause();
    await port.seek(const Duration(seconds: 2), 1);
    expect(commands, containsAllInOrder([
      'prepare', 'play', 'pause', 'seek'
    ]));
    await port.stop();
    await port.dispose();
  });

  test('RC120 old seek generations and stopped source never supply bytes',
      () async {
    final port = FableNativeProtectedPlayerPort(25);
    await port.prepare(const ProtectedPlayerMetadata(
        totalLength: 100, mimeType: 'video/mp4', rangeEpoch: 0),
      (request) async => ProtectedPlayerBytes(
        chunk(request.start, request.length)));
    await port.seek(const Duration(milliseconds: 30), 1);
    final oldRead =
      await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
        const MethodCall('readRange', <String, Object>{
          'viewId': 25, 'requestId': 2, 'start': 10,
          'length': 2, 'rangeEpoch': 0,
        }));
    expect((oldRead as Map)['status'], 'rejected');
    await port.stop();
    final newer =
      await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
        const MethodCall('readRange', <String, Object>{
          'viewId': 25, 'requestId': 3, 'start': 10,
          'length': 2, 'rangeEpoch': 1,
        }));
    expect((newer as Map)['status'], 'rejected');
    await port.dispose();
  });

  test('RC120 disposed platform ID cannot be reused by stale callbacks',
      () async {
    final port = FableNativeProtectedPlayerPort(26);
    await port.prepare(const ProtectedPlayerMetadata(
        totalLength: 100, mimeType: 'video/mp4', rangeEpoch: 0),
      (request) async => ProtectedPlayerBytes(
        chunk(request.start, request.length)));
    await port.dispose();
    final result =
      await FableNativeProtectedPlayerPort.handleNativeCallForTesting(
        const MethodCall('readRange', <String, Object>{
          'viewId': 26, 'requestId': 4,
          'start': 10, 'length': 2, 'rangeEpoch': 0,
        }));
    expect((result as Map)['status'], 'rejected');
  });
}
