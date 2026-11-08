import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../domain/media_byte_range.dart';
import '../domain/media_byte_chunk.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';

/// RC130: Fable-only authenticated-by-guest-lease media range source.
/// A guest needs NO user login. The *storage* URL remains private.
/// Security invariant: the client never exposes a media Token in any URI,
/// never retains it in preferences/disk and never follows redirects.
final class FablePublicGuestByteSource implements DescribedMediaByteSource {
  FablePublicGuestByteSource({
    required Dio client,
    required Uri origin,
    required String assetId,
  }) : _dio = client, _origin = origin, _assetId = assetId {
    if (kIsWeb) {
      throw UnsupportedError(
        'Flutter Web must use the BFF/browser guest viewer: '
        'HttpOnly cookies are not readable from JavaScript');
    }
    if (origin.scheme != 'https' || origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        origin.hasQuery || origin.hasFragment ||
        !_uuidV4.hasMatch(assetId)) {
      throw ArgumentError('Guest media requires a verified HTTPS origin and UUIDv4');
    }
  }

  static final _uuidV4 = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$');
  static final _hex64 = RegExp(r'^[a-f0-9]{64}$');
  static final _cookieValue =
      RegExp(r'__Host-fable-media-guest=([a-f0-9]{64})(?:;|$)');

  final Dio _dio;
  final Uri _origin;
  final String _assetId;
  final _notifications =
      StreamController<MediaSessionInvalidation>.broadcast(sync: true);
  final _pending = <CancelToken>{};

  String? _cookie;
  String? _token;
  DateTime? _expiresAt;
  int _generation = 0;
  bool _closed = false;

  Uri _route(String suffix) =>
      _origin.resolve('/media/guest/$_assetId/$suffix');

  void _invalidate(MediaSessionInvalidation why) {
    _generation++;
    _cookie = null;
    _token = null;
    _expiresAt = null;
    for (final cancellation in _pending.toList()) {
      cancellation.cancel('Guest media lease changed');
    }
    _pending.clear();
    if (!_notifications.isClosed) _notifications.add(why);
  }

  @override
  Stream<MediaSessionInvalidation> get invalidations =>
      _notifications.stream;

  @override
  bool get isActive =>
      !_closed &&
      _cookie != null && _token != null &&
      _expiresAt != null &&
      DateTime.now().toUtc().isBefore(_expiresAt!);

  @override
  DateTime get authorizationDeadline =>
      _expiresAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Future<void> open() async {
    if (_closed || isActive || _token != null) {
      throw StateError('Guest media lease already active or source closed');
    }
    final generation = ++_generation;
    final response = await _dio.postUri<Object?>(
      _route('session'),
      options: Options(
        followRedirects: false,
        headers: const {'Accept': 'application/json'},
        validateStatus: (status) => status == 200 || status == 201,
      ),
    );
    if (_closed || generation != _generation) {
      throw StateError('Superseded guest media session');
    }
    final value = response.data;
    final data = value is Map ? value : null;
    final token = data?['token'];
    final identifier = data?['assetId'];
    final endpoint = data?['contentEndpoint'];
    final expiry = data?['expiresAt'];
    final setCookie = response.headers.value('set-cookie') ?? '';
    final cookie = _cookieValue.firstMatch(setCookie)?.group(1);
    final expires = expiry is String ? DateTime.tryParse(expiry)?.toUtc() : null;
    if (token is! String || !_hex64.hasMatch(token) ||
        cookie == null || identifier != _assetId ||
        endpoint != '/media/guest/$_assetId/content' ||
        expires == null ||
        expires.difference(DateTime.now().toUtc()) <= Duration.zero ||
        expires.difference(DateTime.now().toUtc()) >
            const Duration(minutes: 5)) {
      throw const FormatException('Untrusted guest media lease response');
    }
    // Secrets live exclusively in this transient data adapter instance.
    _cookie = cookie;
    _token = token;
    _expiresAt = expires;
  }

  @override
  void cancelPendingReads() {
    for (final cancellation in _pending.toList()) {
      cancellation.cancel('Guest read cancelled');
    }
    _pending.clear();
  }

  @override
  Future<Uint8List> read(MediaByteRange range) async {
    final chunk = await readChunk(range);
    // The compatibility await creates another revoke/expiry boundary.
    if (!isActive) {
      throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    }
    return chunk.bytes;
  }

  @override
  Future<MediaByteChunk> readChunk(MediaByteRange range) async {
    if (!range.isValid) {
      throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    }
    if (!isActive) {
      _invalidate(MediaSessionInvalidation.sourceClosed);
      throw const MediaReadFailure(MediaReadFailureKind.expired);
    }
    final generation = _generation;
    final cookie = _cookie!;
    final token = _token!;
    final cancellation = CancelToken();
    _pending.add(cancellation);
    try {
      final response = await _dio.getUri<Object?>(
        _route('content'),
        cancelToken: cancellation,
        options: Options(
          followRedirects: false,
          responseType: ResponseType.bytes,
          headers: {
            'Cookie': '__Host-fable-media-guest=$cookie',
            'X-Fable-Guest-Media-Token': token,
            'Range': 'bytes=${range.start}-${range.start + range.length - 1}',
            'Accept': '*/*',
            'Cache-Control': 'no-store',
          },
          validateStatus: (status) => status == 206,
        ),
      );
      if (!isActive || _generation != generation || cancellation.isCancelled) {
        throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
      }
      if (response.statusCode != 206) {
        throw const MediaReadFailure(MediaReadFailureKind.invalidResponse);
      }
      final responseRange = response.headers.value('content-range');
      final parsed = responseRange == null ? null :
          RegExp(r'^bytes ([0-9]+)-([0-9]+)/([0-9]+)$')
            .firstMatch(responseRange);
      final start = int.tryParse(parsed?.group(1) ?? '');
      final end = int.tryParse(parsed?.group(2) ?? '');
      final total = int.tryParse(parsed?.group(3) ?? '');
      final expectedEnd = total == null
          ? -1 : (range.start + range.length - 1 < total
              ? range.start + range.length - 1 : total - 1);
      final length = int.tryParse(
          response.headers.value('content-length') ?? '');
      final mime = (response.headers.value('content-type') ?? '').toLowerCase();
      final cache = (response.headers.value('cache-control') ?? '').toLowerCase();
      final bytes = response.data;
      if (start != range.start || end == null || total == null ||
          total <= 0 || end != expectedEnd ||
          length != end - start! + 1 ||
          !cache.contains('no-store') ||
          mime.isEmpty || mime.startsWith('text/html') ||
          bytes is! List<int> || bytes.length != length) {
        throw const MediaReadFailure(MediaReadFailureKind.invalidResponse);
      }
      return MediaByteChunk(start: range.start, totalLength: total,
          mimeType: mime, bytes: Uint8List.fromList(bytes));
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const MediaReadFailure(MediaReadFailureKind.cancelled);
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403 ||
          error.response?.statusCode == 404) {
        _invalidate(MediaSessionInvalidation.sourceClosed);
        throw const MediaReadFailure(MediaReadFailureKind.forbidden);
      }
      throw const MediaReadFailure(MediaReadFailureKind.offline);
    } finally {
      _pending.remove(cancellation);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    final cookie = _cookie, token = _token;
    _closed = true;
    _invalidate(MediaSessionInvalidation.sourceClosed);
    if (cookie != null && token != null) {
      try {
        await _dio.deleteUri<void>(
          _route('session'),
          options: Options(
            followRedirects: false,
            headers: {
              'Cookie': '__Host-fable-media-guest=$cookie',
              'X-Fable-Guest-Media-Token': token,
            },
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
      } catch (_) {
        // Server TTL remains authoritative when network revoke fails.
      }
    }
    await _notifications.close();
  }
}
