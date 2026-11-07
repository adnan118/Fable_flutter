import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fable_media/fable_media.dart';

/// Original 8-second H264 Baseline MP4, generated locally for RC124.
/// The only input is local audited bytes, never a Backend URL or credential.
final class Rc124FixtureSource implements DescribedMediaByteSource {
  Rc124FixtureSource(this.bytes, {this.blockNative = false})
      : _deadline = DateTime.now().toUtc().add(const Duration(minutes: 4));

  final Uint8List bytes;
  final bool blockNative;
  final DateTime _deadline;
  final _events =
      StreamController<MediaSessionInvalidation>.broadcast(sync: true);
  final Completer<void> nativeReadStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool active = true;
  int reads = 0;
  int cancels = 0;
  int closes = 0;

  @override
  bool get isActive => active;
  @override
  DateTime get authorizationDeadline => _deadline;
  @override
  Stream<MediaSessionInvalidation> get invalidations => _events.stream;

  @override
  Future<MediaByteChunk> readChunk(MediaByteRange range) async {
    if (!active || range.start < 0 || range.start >= bytes.length) {
      throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    }
    reads++;
    if (blockNative && reads >= 2) {
      if (!nativeReadStarted.isCompleted) nativeReadStarted.complete();
      // Deliberately return stale data AFTER account revocation, simulating
      // a storage/API callback which raced cancellation. The broker/lease,
      // not a cooperative fake transport, must reject it.
      await _release.future;
    }
    final end = math.min(bytes.length, range.start + range.length);
    return MediaByteChunk(
      start: range.start, totalLength: bytes.length, mimeType: 'video/mp4',
      bytes: Uint8List.fromList(bytes.sublist(range.start, end)),
    );
  }

  @override
  Future<Uint8List> read(MediaByteRange range) async =>
      (await readChunk(range)).bytes;

  void revoke() {
    if (!active) return;
    active = false;
    _events.add(MediaSessionInvalidation.accountChanged);
  }

  void releaseLateRead() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  void cancelPendingReads() { cancels++; }

  @override
  Future<void> close() async {
    if (closes++ > 0) return;
    revoke();
    releaseLateRead();
    await _events.close();
  }
}

Future<Uint8List> fixtureBytes() async {
  final data = await rootBundle.load('assets/videos/rc124_blue_h264_8s.mp4');
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes, data.lengthInBytes);
  expect(bytes.length, 2279, reason: 'RC124 fixture must be 2279 bytes');
  return bytes;
}

Future<T> within<T>(WidgetTester tester, Future<T> future,
    {int seconds = 50}) async {
  final result = await tester.runAsync(
    () => future.timeout(Duration(seconds: seconds)));
  // Future<void> correctly resolves to null; non-null sessions retain type.
  return result as T;
}

Future<void> waitForClose(Rc124FixtureSource source) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (source.closes == 0) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Native surface did not close protected source');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RC124 real native playing/paused/seeked/resumed/ended', (tester) async {
    final source = Rc124FixtureSource(await fixtureBytes());
    final sessionReady = Completer<ProtectedPlayerSession>();
    final nativeReady = Completer<void>();
    final firstPlaying = Completer<void>();
    final nativePaused = Completer<void>();
    final seeked = Completer<void>();
    final resumed = Completer<void>();
    final ended = Completer<void>();
    final events = <FableNativePlayerEventKind>[];

    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 160, height: 160,
        child: FableNativeProtectedPlayerSurface(
          source: source,
          onSessionReady: (s) {
            if (!sessionReady.isCompleted) sessionReady.complete(s);
          },
          onNativeEvent: (e) {
            events.add(e.kind);
            switch (e.kind) {
              case FableNativePlayerEventKind.ready:
                if (!nativeReady.isCompleted) nativeReady.complete();
              case FableNativePlayerEventKind.playing:
                if (!firstPlaying.isCompleted) firstPlaying.complete();
                if (seeked.isCompleted && !resumed.isCompleted) {
                  resumed.complete();
                }
              case FableNativePlayerEventKind.paused:
                if (!nativePaused.isCompleted) nativePaused.complete();
              case FableNativePlayerEventKind.seeked:
                if (e.rangeEpoch == 1 && !seeked.isCompleted) {
                  seeked.complete();
                }
              case FableNativePlayerEventKind.ended:
                if (!ended.isCompleted) ended.complete();
              case FableNativePlayerEventKind.failed:
                fail('Native decoder failed during pause/seek/resume');
            }
          },
        ),
      ),
    )));
    final session = await within(tester, sessionReady.future);
    await within(tester, nativeReady.future, seconds: 70);
    expect(session.state.phase, ProtectedPlayerPhase.ready);
    expect(source.reads, greaterThanOrEqualTo(2));

    await session.play();
    await within(tester, firstPlaying.future, seconds: 20);
    await session.pause();
    await within(tester, nativePaused.future, seconds: 20);
    expect(session.state.phase, ProtectedPlayerPhase.paused);

    await session.seek(const Duration(seconds: 5));
    await within(tester, seeked.future, seconds: 30);
    expect(session.state.phase, ProtectedPlayerPhase.paused);

    await session.play();
    await within(tester, resumed.future, seconds: 25);
    await within(tester, ended.future, seconds: 30);
    expect(events, containsAllInOrder([
      FableNativePlayerEventKind.playing,
      FableNativePlayerEventKind.paused,
      FableNativePlayerEventKind.seeked,
      FableNativePlayerEventKind.playing,
      FableNativePlayerEventKind.ended,
    ]));
    expect(events, isNot(contains(FableNativePlayerEventKind.failed)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await within(tester, waitForClose(source), seconds: 12);
    expect(source.closes, 1);
    expect(session.state.phase, ProtectedPlayerPhase.disposed);
  });

  testWidgets('RC124 account invalidation rejects a pending native range',
      (tester) async {
    final source = Rc124FixtureSource(
      await fixtureBytes(), blockNative: true);
    final sessionReady = Completer<ProtectedPlayerSession>();
    final events = <FableNativePlayerEventKind>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 160, height: 160,
        child: FableNativeProtectedPlayerSurface(
          source: source,
          onSessionReady: (s) {
            if (!sessionReady.isCompleted) sessionReady.complete(s);
          },
          onNativeEvent: (e) => events.add(e.kind),
        ),
      ),
    )));
    final session = await within(tester, sessionReady.future);
    await within(tester, source.nativeReadStarted.future, seconds: 60);
    expect(session.state.phase, ProtectedPlayerPhase.ready);
    final readsBeforeRevocation = source.reads;
    source.revoke();
    expect(session.state.phase, ProtectedPlayerPhase.revoked);
    expect(source.cancels, greaterThan(0));
    source.releaseLateRead();
    await within(tester, Future<void>.delayed(
      const Duration(milliseconds: 400)), seconds: 3);
    expect(source.reads, readsBeforeRevocation,
        reason: 'Revoked source must not start any more reads');
    expect(events, isNot(contains(FableNativePlayerEventKind.ready)));
    expect(events, isNot(contains(FableNativePlayerEventKind.playing)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await within(tester, waitForClose(source), seconds: 12);
    expect(source.closes, 1);
    expect(session.state.phase, ProtectedPlayerPhase.disposed);
  });
}
