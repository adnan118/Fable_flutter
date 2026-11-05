import 'dart:async';
import '../domain/media_byte_chunk.dart';
import '../domain/media_byte_range.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';
import '../domain/protected_player_port.dart';

/// Session-scoped, fail-closed mediator for a *verified progressive* source.
/// Native devices still require a separately implemented/tested renderer port.
final class ProtectedPlayerSession {
  ProtectedPlayerSession({
    required DescribedMediaByteSource source,
    required ProtectedPlayerPlatformPort platform,
    this.maxConcurrentReads = 2,
    this.probeBytes = 32 * 1024,
    this.rangeTimeout = const Duration(seconds: 15),
  })  : _source = source,
        _platform = platform {
    if (maxConcurrentReads < 1 || maxConcurrentReads > 4 ||
        probeBytes < 1 || probeBytes > MediaByteRange.maxLength ||
        rangeTimeout <= Duration.zero ||
        rangeTimeout > const Duration(minutes: 2)) {
      throw ArgumentError('Invalid player buffering limits');
    }
    _subscription = source.invalidations.listen((reason) {
      _revoke(reason);
    });
  }

  final DescribedMediaByteSource _source;
  final ProtectedPlayerPlatformPort _platform;
  final int maxConcurrentReads;
  final int probeBytes;
  final Duration rangeTimeout;
  final StreamController<ProtectedPlayerState> _states =
      StreamController<ProtectedPlayerState>.broadcast(sync: true);
  final Map<int, int> _inFlight = <int, int>{};
  StreamSubscription<MediaSessionInvalidation>? _subscription;
  Timer? _expiryTimer;
  ProtectedPlayerState _state =
      const ProtectedPlayerState(ProtectedPlayerPhase.idle);
  ProtectedPlayerMetadata? _metadata;
  int _epoch = 0;
  int _rangeEpoch = 0;
  bool _disposed = false;
  bool _commandBusy = false;

  ProtectedPlayerState get state => _state;
  Stream<ProtectedPlayerState> get states => _states.stream;

  bool get _authorized =>
      !_disposed &&
      _source.isActive &&
      DateTime.now().toUtc().isBefore(_source.authorizationDeadline);

  bool _current(int epoch) =>
      epoch == _epoch && _authorized &&
      _state.phase != ProtectedPlayerPhase.revoked &&
      _state.phase != ProtectedPlayerPhase.stopped &&
      _state.phase != ProtectedPlayerPhase.failed &&
      _state.phase != ProtectedPlayerPhase.disposed;

  void _emit(ProtectedPlayerPhase phase, {MediaReadFailureKind? error}) {
    if (_disposed || _states.isClosed) return;
    _state = ProtectedPlayerState(phase, failure: error);
    _states.add(_state);
  }

  void _cancelRanges() {
    _rangeEpoch++;
    _inFlight.clear();
    _source.cancelPendingReads();
  }

  Future<void> _stopNative() async {
    try {
      // Call immediately, never postpone past a microtask on revocation.
      await _platform.stop();
    } catch (_) {
      // Stale/revoked player must never be revived on a cleanup failure.
    }
  }

  void _revoke(MediaSessionInvalidation reason) {
    if (_disposed || _state.phase == ProtectedPlayerPhase.revoked ||
        _state.phase == ProtectedPlayerPhase.stopped) return;
    _epoch++;
    _expiryTimer?.cancel();
    _cancelRanges();
    _metadata = null;
    _emit(ProtectedPlayerPhase.revoked,
        error: MediaReadFailureKind.sessionChanged);
    unawaited(_stopNative());
  }

  void _fail(MediaReadFailureKind reason) {
    if (_disposed || _state.phase == ProtectedPlayerPhase.revoked ||
        _state.phase == ProtectedPlayerPhase.stopped ||
        _state.phase == ProtectedPlayerPhase.failed) return;
    _epoch++;
    _expiryTimer?.cancel();
    _cancelRanges();
    _metadata = null;
    _emit(ProtectedPlayerPhase.failed, error: reason);
    unawaited(_stopNative());
  }

  void _armExpiry() {
    _expiryTimer?.cancel();
    final delay = _source.authorizationDeadline.difference(
      DateTime.now().toUtc(),
    );
    if (delay <= Duration.zero) {
      _revoke(MediaSessionInvalidation.sourceClosed);
    } else {
      _expiryTimer = Timer(delay, () =>
          _revoke(MediaSessionInvalidation.sourceClosed));
    }
  }

  /// An initial verified read establishes total size and MIME. The probe
  /// buffer is not cached; the native port must request its own bounded bytes.
  Future<void> prepare() async {
    if (_state.phase != ProtectedPlayerPhase.idle) {
      throw StateError('Player already prepared or closed');
    }
    if (!_authorized) {
      _revoke(MediaSessionInvalidation.sourceClosed);
      return;
    }
    final operation = ++_epoch;
    _emit(ProtectedPlayerPhase.preparing);
    try {
      final first = await _source.readChunk(
          MediaByteRange(start: 0, length: probeBytes)).timeout(rangeTimeout);
      if (!_authorized) {
        _revoke(MediaSessionInvalidation.sourceClosed);
        return;
      }
      if (!_current(operation)) return;
      _metadata = ProtectedPlayerMetadata(
          totalLength: first.totalLength, mimeType: first.mimeType,
          rangeEpoch: _rangeEpoch);
      _armExpiry();
      if (!_current(operation)) return;
      await _platform.prepare(_metadata!, readRange);
      if (!_current(operation)) {
        // Even if an older asynchronous native prepare completes after stop,
        // repeat teardown so it cannot reactivate the old renderer.
        await _stopNative();
        return;
      }
      _emit(ProtectedPlayerPhase.ready);
    } on MediaReadFailure catch (error) {
      if (!_authorized) {
        _revoke(MediaSessionInvalidation.sourceClosed);
      } else if (_current(operation)) {
        _fail(error.kind);
      }
    } on TimeoutException {
      if (_current(operation)) _fail(MediaReadFailureKind.timedOut);
    } catch (_) {
      if (!_authorized) {
        _revoke(MediaSessionInvalidation.sourceClosed);
      } else if (_current(operation)) {
        _fail(MediaReadFailureKind.unknown);
      }
    }
  }

  bool get _canServe =>
      _authorized &&
      _metadata != null &&
      {
        ProtectedPlayerPhase.preparing,
        ProtectedPlayerPhase.ready,
        ProtectedPlayerPhase.playing,
        ProtectedPlayerPhase.paused,
      }.contains(_state.phase);

  /// Native request IDs have meaning only within this specific session.
  /// Invalid, duplicate, excessive, and stale requests never reach Backend.
  Future<ProtectedPlayerReadReply> readRange(
      ProtectedPlayerReadRequest request) async {
    if (!_canServe) {
      if (!_authorized) _revoke(MediaSessionInvalidation.sourceClosed);
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.sessionChanged);
    }
    final metadata = _metadata!;
    if (request.rangeEpoch != _rangeEpoch) {
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.sessionChanged);
    }
    if (request.requestId <= 0 || request.start < 0 ||
        request.start > metadata.totalLength || request.length <= 0 ||
        request.length > MediaByteRange.maxLength ||
        request.start > 0x7fffffffffffffff - request.length) {
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.invalidInput);
    }
    if (request.start == metadata.totalLength) {
      return const ProtectedPlayerEndOfFile();
    }
    if (_inFlight.containsKey(request.requestId)) {
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.invalidInput);
    }
    if (_inFlight.length >= maxConcurrentReads) {
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.rateLimited);
    }
    final epoch = _epoch;
    final rangeEpoch = _rangeEpoch;
    _inFlight[request.requestId] = rangeEpoch;
    try {
      final chunk = await _source.readChunk(MediaByteRange(
          start: request.start, length: request.length))
          .timeout(rangeTimeout);
      if (!_authorized) {
        _revoke(MediaSessionInvalidation.sourceClosed);
      }
      if (!_current(epoch) || rangeEpoch != _rangeEpoch || !_canServe) {
        return const ProtectedPlayerReadRejected(
            MediaReadFailureKind.sessionChanged);
      }
      if (chunk.start != request.start ||
          chunk.length > request.length ||
          chunk.totalLength != metadata.totalLength ||
          chunk.mimeType != metadata.mimeType) {
        _revoke(MediaSessionInvalidation.resourceChanged);
        return const ProtectedPlayerReadRejected(
            MediaReadFailureKind.invalidResponse);
      }
      return ProtectedPlayerBytes(chunk);
    } on MediaReadFailure catch (error) {
      if (!_authorized) _revoke(MediaSessionInvalidation.sourceClosed);
      if (!_current(epoch) || rangeEpoch != _rangeEpoch) {
        return const ProtectedPlayerReadRejected(
            MediaReadFailureKind.sessionChanged);
      }
      _fail(error.kind);
      return ProtectedPlayerReadRejected(error.kind);
    } on TimeoutException {
      if (_current(epoch) && rangeEpoch == _rangeEpoch) {
        _fail(MediaReadFailureKind.timedOut);
      }
      return const ProtectedPlayerReadRejected(MediaReadFailureKind.timedOut);
    } catch (_) {
      if (!_authorized) _revoke(MediaSessionInvalidation.sourceClosed);
      if (!_current(epoch) || rangeEpoch != _rangeEpoch) {
        return const ProtectedPlayerReadRejected(
            MediaReadFailureKind.sessionChanged);
      }
      _fail(MediaReadFailureKind.unknown);
      return const ProtectedPlayerReadRejected(
          MediaReadFailureKind.unknown);
    } finally {
      if (_inFlight[request.requestId] == rangeEpoch) {
        _inFlight.remove(request.requestId);
      }
    }
  }

  /// Decoder failures arrive asynchronously after native prepare/play().
  /// A successful method-channel acknowledgement is NOT decoded playback.
  /// The renderer must be stopped and pending byte ranges rejected.
  void reportRendererFailure() {
    if (_disposed || _state.phase == ProtectedPlayerPhase.revoked ||
        _state.phase == ProtectedPlayerPhase.stopped ||
        _state.phase == ProtectedPlayerPhase.failed) return;
    _fail(MediaReadFailureKind.unsupported);
  }

  Future<void> play() async {
    if (!_authorized) {
      _revoke(MediaSessionInvalidation.sourceClosed);
      return;
    }
    if (_commandBusy ||
        !{ProtectedPlayerPhase.ready, ProtectedPlayerPhase.paused}
            .contains(_state.phase)) {
      throw StateError('Player is not ready to play');
    }
    final epoch = _epoch;
    _commandBusy = true;
    try {
      await _platform.play();
      if (_current(epoch)) {
        _emit(ProtectedPlayerPhase.playing);
      } else {
        await _stopNative();
      }
    } catch (_) {
      if (_current(epoch)) _fail(MediaReadFailureKind.unknown);
    } finally {
      _commandBusy = false;
    }
  }

  Future<void> pause() async {
    if (!_authorized) {
      _revoke(MediaSessionInvalidation.sourceClosed);
      return;
    }
    if (_commandBusy || _state.phase != ProtectedPlayerPhase.playing) {
      throw StateError('Player is not playing');
    }
    final epoch = _epoch;
    _commandBusy = true;
    try {
      await _platform.pause();
      if (_current(epoch)) {
        _emit(ProtectedPlayerPhase.paused);
      } else {
        await _stopNative();
      }
    } catch (_) {
      if (_current(epoch)) _fail(MediaReadFailureKind.unknown);
    } finally {
      _commandBusy = false;
    }
  }

  Future<void> seek(Duration position) async {
    if (position.isNegative) throw ArgumentError('Negative seek position');
    if (!_authorized) {
      _revoke(MediaSessionInvalidation.sourceClosed);
      return;
    }
    if (_commandBusy ||
        !{ProtectedPlayerPhase.ready, ProtectedPlayerPhase.playing,
          ProtectedPlayerPhase.paused}.contains(_state.phase)) {
      throw StateError('Player cannot seek in current state');
    }
    final epoch = _epoch;
    _commandBusy = true;
    _cancelRanges();
    try {
      await _platform.seek(position, _rangeEpoch);
      if (!_current(epoch)) await _stopNative();
    } catch (_) {
      if (_current(epoch)) _fail(MediaReadFailureKind.unknown);
    } finally {
      _commandBusy = false;
    }
  }

  /// Local stop is not Backend DELETE / revoke. Server end is owner-controlled.
  Future<void> stop() async {
    if (_disposed || _state.phase == ProtectedPlayerPhase.stopped ||
        _state.phase == ProtectedPlayerPhase.revoked) return;
    _epoch++;
    _expiryTimer?.cancel();
    _cancelRanges();
    _metadata = null;
    _emit(ProtectedPlayerPhase.stopped);
    await _stopNative();
  }

  /// This instance is terminal. A new account/playback must create a new port,
  /// source and controller. Closing the source does not end Backend playback.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _expiryTimer?.cancel();
    _cancelRanges();
    _metadata = null;
    _state = const ProtectedPlayerState(ProtectedPlayerPhase.disposed);
    await _subscription?.cancel();
    await _stopNative();
    try {
      await _platform.dispose();
    } finally {
      try {
        await _source.close();
      } finally {
        await _states.close();
      }
    }
  }
}
