import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../application/protected_player_session.dart';
import '../domain/protected_player_port.dart';

/// RC120: concrete Flutter -> Android Media3 / iOS AVFoundation transport.
/// Native receives only opaque platform-view identity, verified content length,
/// MIME and bounded source byte buffers. No bearer, media token or backend URL.
final class FableNativeProtectedPlayerPort implements ProtectedPlayerPlatformPort {
  FableNativeProtectedPlayerPort(int viewId) : _viewId = viewId {
    if (viewId < 0 || _ports.containsKey(viewId)) {
      throw StateError('Invalid or already bound protected player view');
    }
    _ports[viewId] = this;
    _registerOnce();
  }

  static const String viewType = 'fable/protected_media_surface';
  static const MethodChannel channel = MethodChannel('fable/protected_player_v1');
  static final Map<int, FableNativeProtectedPlayerPort> _ports = {};
  static bool _listening = false;

  static void _registerOnce() {
    if (_listening) return;
    channel.setMethodCallHandler(_handleNativeCall);
    _listening = true;
  }

  @visibleForTesting
  static Future<Object?> handleNativeCallForTesting(MethodCall call) =>
      _handleNativeCall(call);

  static Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'readRange') {
      throw MissingPluginException('Unsupported protected media call');
    }
    final args = call.arguments;
    if (args is! Map) return const <String, Object>{'status': 'rejected'};
    final viewId = args['viewId'];
    final requestId = args['requestId'];
    final start = args['start'];
    final length = args['length'];
    final epoch = args['rangeEpoch'];
    if (viewId is! int || requestId is! int || start is! int ||
        length is! int || epoch is! int || requestId <= 0 ||
        start < 0 || length <= 0 || length > 512 * 1024) {
      return const <String, Object>{'status': 'rejected'};
    }
    final port = _ports[viewId];
    final reader = port?._reader;
    if (port == null || port._closed || reader == null ||
        port._rangeEpoch != epoch) {
      return const <String, Object>{'status': 'rejected'};
    }
    final generation = port._generation;
    try {
      final reply = await reader(ProtectedPlayerReadRequest(
        requestId: requestId, start: start,
        length: length, rangeEpoch: epoch,
      ));
      if (port._closed || port._reader != reader ||
          port._generation != generation || port._rangeEpoch != epoch) {
        return const <String, Object>{'status': 'rejected'};
      }
      return switch (reply) {
        ProtectedPlayerBytes(:final chunk) => <String, Object>{
          'status': 'bytes',
          'start': chunk.start,
          'totalLength': chunk.totalLength,
          'mimeType': chunk.mimeType,
          'bytes': chunk.bytes,
        },
        ProtectedPlayerEndOfFile() =>
          const <String, Object>{'status': 'eof'},
        ProtectedPlayerReadRejected() =>
          const <String, Object>{'status': 'rejected'},
      };
    } catch (_) {
      // Never pass exception messages or Backend data across the native port.
      return const <String, Object>{'status': 'rejected'};
    }
  }

  final int _viewId;
  ProtectedPlayerRangeReader? _reader;
  int _generation = 0;
  int _rangeEpoch = 0;
  bool _closed = false;

  Future<void> _invoke(String action, [Map<String, Object>? extra]) async {
    if (_closed) throw StateError('Native protected player was disposed');
    await channel.invokeMethod<void>(action, <String, Object>{
      'viewId': _viewId,
      if (extra != null) ...extra,
    });
  }

  @override
  Future<void> prepare(ProtectedPlayerMetadata metadata,
      ProtectedPlayerRangeReader read) async {
    if (_closed || _reader != null || metadata.totalLength <= 0 ||
        metadata.rangeEpoch < 0 ||
        !RegExp(r'^(audio|video)/[a-z0-9][a-z0-9.+_-]*$')
            .hasMatch(metadata.mimeType)) {
      throw StateError('Invalid native player preparation');
    }
    _reader = read;
    _rangeEpoch = metadata.rangeEpoch;
    final generation = ++_generation;
    try {
      await _invoke('prepare', <String, Object>{
        'totalLength': metadata.totalLength,
        'mimeType': metadata.mimeType,
        'rangeEpoch': metadata.rangeEpoch,
      });
      if (_generation != generation || _closed) {
        throw StateError('Native preparation belongs to an old session');
      }
    } catch (_) {
      _reader = null;
      _generation++;
      rethrow;
    }
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seek(Duration position, int rangeEpoch) async {
    if (position.isNegative || rangeEpoch <= _rangeEpoch || _reader == null) {
      throw StateError('Invalid protected player seek');
    }
    _rangeEpoch = rangeEpoch;
    _generation++;
    await _invoke('seek', <String, Object>{
      'millis': position.inMilliseconds,
      'rangeEpoch': rangeEpoch,
    });
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    // First reject all in-flight/queued callbacks, then release native frame
    // buffers. Stopping this UI does NOT end the authoritative server session.
    _generation++;
    _reader = null;
    await _invoke('stop');
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _reader = null;
    _generation++;
    try {
      await _invoke('dispose');
    } finally {
      _closed = true;
      if (identical(_ports[_viewId], this)) _ports.remove(_viewId);
    }
  }
}

/// Hosts a native decoder only after the platform view is actually created.
/// The parent receives a typed session for explicit play/pause/seek/stop.
/// Do not reuse the old session when Auth/backend/asset source changes.
final class FableNativeProtectedPlayerSurface extends StatefulWidget {
  const FableNativeProtectedPlayerSurface({
    super.key,
    required this.source,
    required this.onSessionReady,
  });

  final DescribedMediaByteSource source;
  final ValueChanged<ProtectedPlayerSession> onSessionReady;

  @override
  State<FableNativeProtectedPlayerSurface> createState() =>
      _FableNativeProtectedPlayerSurfaceState();
}

final class _FableNativeProtectedPlayerSurfaceState
    extends State<FableNativeProtectedPlayerSurface>
    with WidgetsBindingObserver {
  int? _viewId;
  int _bindingRevision = 0;
  ProtectedPlayerSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant FableNativeProtectedPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) && _viewId != null) {
      unawaited(_bind(_viewId!));
    }
  }

  Future<void> _bind(int viewId) async {
    final revision = ++_bindingRevision;
    final prior = _session;
    _session = null;
    if (prior != null) await prior.dispose();
    if (!mounted || revision != _bindingRevision) return;

    final port = FableNativeProtectedPlayerPort(viewId);
    final session = ProtectedPlayerSession(
      source: widget.source, platform: port,
    );
    _session = session;
    try {
      await session.prepare();
      if (!mounted || revision != _bindingRevision) {
        await session.dispose();
        return;
      }
      if (session.state.phase == ProtectedPlayerPhase.ready) {
        widget.onSessionReady(session);
      }
    } catch (_) {
      await session.dispose();
    }
  }

  void _created(int id) {
    _viewId = id;
    unawaited(_bind(id));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final session = _session;
      if (session != null) unawaited(session.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: FableNativeProtectedPlayerPort.viewType,
        onPlatformViewCreated: _created,
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: FableNativeProtectedPlayerPort.viewType,
        onPlatformViewCreated: _created,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  void dispose() {
    ++_bindingRevision;
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }
}
