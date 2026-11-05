import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fable_media/fable_media.dart';

/// A deterministic, local MP4 source. The native decoder still consumes
/// ONLY the production SessionBound ByteSource -> Dart lease -> range channel;
/// the source deliberately has no HTTP, Backend session or bearer token.
final class Rc122FixtureSource implements DescribedMediaByteSource {
  Rc122FixtureSource(this.bytes)
      : _deadline = DateTime.now().toUtc().add(const Duration(minutes: 3));

  final Uint8List bytes;
  final DateTime _deadline;
  final StreamController<MediaSessionInvalidation> _invalidations =
      StreamController<MediaSessionInvalidation>.broadcast(sync: true);
  bool active = true;
  int rangeReadCount = 0;
  int cancellationCount = 0;
  int closeCount = 0;

  @override
  bool get isActive => active;

  @override
  DateTime get authorizationDeadline => _deadline;

  @override
  Stream<MediaSessionInvalidation> get invalidations => _invalidations.stream;

  @override
  Future<MediaByteChunk> readChunk(MediaByteRange range) async {
    if (!active || range.start >= bytes.length) {
      throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    }
    rangeReadCount++;
    final end = math.min(bytes.length, range.start + range.length);
    return MediaByteChunk(
      start: range.start,
      totalLength: bytes.length,
      mimeType: 'video/mp4',
      bytes: Uint8List.fromList(bytes.sublist(range.start, end)),
    );
  }

  @override
  Future<Uint8List> read(MediaByteRange range) async =>
      (await readChunk(range)).bytes;

  @override
  void cancelPendingReads() { cancellationCount++; }

  @override
  Future<void> close() async {
    if (!active) return;
    closeCount++;
    active = false;
    _invalidations.add(MediaSessionInvalidation.sourceClosed);
    await _invalidations.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RC122 H264/MP4 native resourceLoader decoder-ready, play and end',
      (tester) async {
    final data = await rootBundle.load('assets/videos/rc122_blue_h264.mp4');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes, data.lengthInBytes);
    expect(bytes.length, 1569, reason: 'Must use the audited 1569-byte MP4');
    final source = Rc122FixtureSource(bytes);
    final onReady = Completer<ProtectedPlayerSession>();
    final onNativeReady = Completer<void>();
    final onNativeEnded = Completer<void>();
    final events = <FableNativePlayerEventKind>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 160,
          child: FableNativeProtectedPlayerSurface(
            source: source,
            onSessionReady: (session) {
              if (!onReady.isCompleted) onReady.complete(session);
            },
            onNativeEvent: (event) {
              events.add(event.kind);
              if (event.kind == FableNativePlayerEventKind.ready &&
                  !onNativeReady.isCompleted) {
                onNativeReady.complete();
              }
              if (event.kind == FableNativePlayerEventKind.ended &&
                  !onNativeEnded.isCompleted) {
                onNativeEnded.complete();
              }
            },
          ),
        ),
      ),
    ));

    final session = await tester.runAsync(() async {
      return onReady.future.timeout(const Duration(seconds: 50));
    });
    expect(session, isNotNull);
    expect(session!.state.phase, ProtectedPlayerPhase.ready);
    expect(source.rangeReadCount, greaterThanOrEqualTo(1),
        reason: 'Source probe must read local fixture bytes');

    await tester.runAsync(() async {
      // A decoder's real ready event (Media3 / AVPlayerItem.status) must
      // arrive. An acknowledged method-channel prepare is not sufficient.
      await Future.any<void>([
        onNativeReady.future,
        Future<void>.delayed(const Duration(seconds: 60), () =>
          throw StateError('Native decoder never became ready: $events')),
      ]);
    });
    expect(events, contains(FableNativePlayerEventKind.ready));
    expect(source.rangeReadCount, greaterThanOrEqualTo(2),
        reason: 'Native decoder must request protected ranges after probe');

    await session.play();
    await tester.runAsync(() async {
      await onNativeEnded.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () => throw StateError(
          'Native decoder did not reach end of stream: $events'),
      );
    });
    expect(events, isNot(contains(FableNativePlayerEventKind.failed)));
    expect(events, contains(FableNativePlayerEventKind.ended));

    // Player end is local: the backend's authoritative playback-end endpoint
    // was never used or simulated in this deterministic media decoder test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(source.cancellationCount, greaterThan(0));
  });
}
