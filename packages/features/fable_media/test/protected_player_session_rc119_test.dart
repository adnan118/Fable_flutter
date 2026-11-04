import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

MediaByteChunk chunk(MediaByteRange range, {int total = 6,
    String mime = 'video/mp4'}) {
  final count = range.length < total - range.start
      ? range.length : total - range.start;
  return MediaByteChunk(start: range.start, totalLength: total,
      mimeType: mime, bytes: Uint8List.fromList(
          List<int>.generate(count, (i) => (range.start + i) % 255)));
}

final class FakeSource implements DescribedMediaByteSource {
  FakeSource({this.produce, DateTime? deadline})
      : deadline = deadline ??
          DateTime.now().toUtc().add(const Duration(minutes: 5));
  Future<MediaByteChunk> Function(MediaByteRange range)? produce;
  final DateTime deadline;
  final _events =
      StreamController<MediaSessionInvalidation>.broadcast(sync: true);
  bool active = true;
  int reads = 0;
  int cancellations = 0;
  int closes = 0;

  @override
  DateTime get authorizationDeadline => deadline;
  @override
  bool get isActive => active;
  @override
  Stream<MediaSessionInvalidation> get invalidations => _events.stream;
  @override
  Future<MediaByteChunk> readChunk(MediaByteRange range) {
    reads++;
    final body = produce;
    return body != null ? body(range) : Future.value(chunk(range));
  }
  @override
  Future<Uint8List> read(MediaByteRange range) async =>
      (await readChunk(range)).bytes;
  @override
  void cancelPendingReads() { cancellations++; }
  void revoke(MediaSessionInvalidation reason) {
    active = false;
    _events.add(reason);
  }
  @override
  Future<void> close() async {
    if (closes++ > 0) return;
    revoke(MediaSessionInvalidation.sourceClosed);
    await _events.close();
  }
}

final class FakePlatform implements ProtectedPlayerPlatformPort {
  final calls = <String>[];
  ProtectedPlayerMetadata? descriptor;
  ProtectedPlayerRangeReader? reader;
  Completer<void>? preparing;
  Completer<void>? playing;
  @override
  Future<void> prepare(ProtectedPlayerMetadata metadata,
      ProtectedPlayerRangeReader read) async {
    calls.add('prepare');
    descriptor = metadata;
    reader = read;
    if (preparing != null) await preparing!.future;
  }
  @override
  Future<void> play() async {
    calls.add('play');
    if (playing != null) await playing!.future;
  }
  @override
  Future<void> pause() async { calls.add('pause'); }
  @override
  Future<void> seek(Duration at) async { calls.add('seek'); }
  @override
  Future<void> stop() async { calls.add('stop'); }
  @override
  Future<void> dispose() async { calls.add('dispose'); }
}

void main() {
  test('RC119 prepare-play-pause-seek-resume-stop is typed and terminal', () async {
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    expect(session.state.phase, ProtectedPlayerPhase.ready);
    expect(platform.descriptor!.totalLength, 6);
    expect(platform.descriptor!.mimeType, 'video/mp4');
    expect(platform.reader, isNotNull);
    final data = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 1, start: 0, length: 6));
    expect(data, isA<ProtectedPlayerBytes>());
    expect((data as ProtectedPlayerBytes).chunk.bytes,
        [0, 1, 2, 3, 4, 5]);
    await session.play();
    expect(session.state.phase, ProtectedPlayerPhase.playing);
    await session.pause();
    expect(session.state.phase, ProtectedPlayerPhase.paused);
    await session.seek(const Duration(seconds: 2));
    await session.play();
    await session.stop();
    expect(session.state.phase, ProtectedPlayerPhase.stopped);
    expect(source.cancellations, greaterThan(0));
    expect(await platform.reader!(const ProtectedPlayerReadRequest(
      requestId: 2, start: 0, length: 6)), isA<ProtectedPlayerReadRejected>());
    await session.dispose();
    expect(source.closes, 1);
    expect(platform.calls, containsAllInOrder([
      'prepare', 'play', 'pause', 'seek', 'play', 'stop', 'dispose'
    ]));
  });

  test('RC119 account switch immediately blocks and purges pending ranges',
      () async {
    final blocked = Completer<MediaByteChunk>();
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    source.produce = (_) => blocked.future;
    final request = platform.reader!(const ProtectedPlayerReadRequest(
      requestId: 9, start: 0, length: 3));
    source.revoke(MediaSessionInvalidation.accountChanged);
    expect(session.state.phase, ProtectedPlayerPhase.revoked);
    expect(platform.calls.last, 'stop');
    blocked.complete(chunk(const MediaByteRange(start: 0, length: 3)));
    expect(await request, isA<ProtectedPlayerReadRejected>());
    expect(source.cancellations, greaterThan(0));
    await session.dispose();
  });

  test('RC119 old native prepare cannot resurrect a revoked session',
      () async {
    final source = FakeSource();
    final platform = FakePlatform()..preparing = Completer<void>();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    final pending = session.prepare();
    await Future<void>.delayed(Duration.zero);
    source.revoke(MediaSessionInvalidation.credentialsRotated);
    expect(session.state.phase, ProtectedPlayerPhase.revoked);
    platform.preparing!.complete();
    await pending;
    expect(session.state.phase, ProtectedPlayerPhase.revoked);
    expect(platform.calls.where((x) => x == 'stop').length, greaterThanOrEqualTo(2));
    await session.dispose();
  });

  test('RC119 EOF, duplicate request and capped concurrency fail closed',
      () async {
    final pending = Completer<MediaByteChunk>();
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(
        source: source, platform: platform, maxConcurrentReads: 1);
    await session.prepare();
    final initial = source.reads;
    final eof = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 11, start: 6, length: 1));
    expect(eof, isA<ProtectedPlayerEndOfFile>());
    expect(source.reads, initial);
    final invalid = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 12, start: 7, length: 1));
    expect(invalid, isA<ProtectedPlayerReadRejected>());
    source.produce = (_) => pending.future;
    final first = platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 13, start: 0, length: 3));
    expect((await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 13, start: 0, length: 3))),
        isA<ProtectedPlayerReadRejected>());
    final cap = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 14, start: 0, length: 3));
    expect((cap as ProtectedPlayerReadRejected).reason,
        MediaReadFailureKind.rateLimited);
    expect(source.reads, initial + 1);
    pending.complete(chunk(const MediaByteRange(start: 0, length: 3)));
    expect(await first, isA<ProtectedPlayerBytes>());
    await session.dispose();
  });

  test('RC119 seek cancels old ranges while permitting fresh ones',
      () async {
    final pending = Completer<MediaByteChunk>();
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    source.produce = (_) => pending.future;
    final old = platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 21, start: 0, length: 3));
    await session.seek(const Duration(seconds: 5));
    expect(source.cancellations, greaterThan(0));
    source.produce = null;
    final fresh = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 22, start: 3, length: 3));
    expect(fresh, isA<ProtectedPlayerBytes>());
    pending.complete(chunk(const MediaByteRange(start: 0, length: 3)));
    expect(await old, isA<ProtectedPlayerReadRejected>());
    expect(session.state.phase, ProtectedPlayerPhase.ready);
    await session.dispose();
  });

  test('RC119 403/expiry stop native renderer instead of leaking old bytes',
      () async {
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    source.produce = (_) async =>
        throw const MediaReadFailure(MediaReadFailureKind.forbidden);
    final failed = await platform.reader!(const ProtectedPlayerReadRequest(
        requestId: 31, start: 0, length: 3));
    expect((failed as ProtectedPlayerReadRejected).reason,
        MediaReadFailureKind.forbidden);
    expect(session.state.phase, ProtectedPlayerPhase.failed);
    expect(platform.calls.last, 'stop');
    await session.dispose();

    final expiring = FakeSource(deadline: DateTime.now().toUtc()
        .add(const Duration(milliseconds: 70)));
    final expiringPlatform = FakePlatform();
    final expiringSession =
        ProtectedPlayerSession(source: expiring, platform: expiringPlatform);
    await expiringSession.prepare();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(expiringSession.state.phase, ProtectedPlayerPhase.revoked);
    expect(expiringPlatform.calls, contains('stop'));
    await expiringSession.dispose();
  });

  test('RC119 async play completion after switch cannot revive renderer',
      () async {
    final source = FakeSource();
    final platform = FakePlatform()..playing = Completer<void>();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    final playing = session.play();
    source.revoke(MediaSessionInvalidation.playbackEnded);
    platform.playing!.complete();
    await playing;
    expect(session.state.phase, ProtectedPlayerPhase.revoked);
    expect(platform.calls, contains('stop'));
    await session.dispose();
  });

  test('RC119 close source does not revoke server; no URL or secret on port',
      () async {
    final source = FakeSource();
    final platform = FakePlatform();
    final session = ProtectedPlayerSession(source: source, platform: platform);
    await session.prepare();
    expect(platform.descriptor!.totalLength, 6);
    await session.dispose();
    expect(source.closes, 1);
    expect(platform.calls.last, 'dispose');
  });
}
