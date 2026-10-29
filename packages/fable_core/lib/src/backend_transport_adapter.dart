import 'fable_contract.dart';
import 'fable_session.dart';

/// The UI and feature packages always speak operationIds through one transport.
/// Only the selected backend adapter decides request headers and session policy.
/// No credentials, API keys, or backend secrets belong in app assets.
enum BackendSessionMode { rotatingBearer, singleBearer, anonymous }

abstract interface class BackendTransportAdapter {
  OperationCatalog get catalog;
  BackendSessionMode get sessionMode;
  Future<Map<String, String>> headersFor(FableOperation operation, FableSecureSession session);
}

/// Fable-specific client metadata follows the Fable Backend HTTP headers contract.
/// x-installation-id is an installation identifier, NOT an authentication proof.
class FableTransportAdapter implements BackendTransportAdapter {
  FableTransportAdapter({required this.catalog, this.language, this.platform, this.appVersion});
  @override final OperationCatalog catalog;
  final String? language;
  final String? platform;
  final String? appVersion;
  @override BackendSessionMode get sessionMode => BackendSessionMode.rotatingBearer;

  @override Future<Map<String, String>> headersFor(FableOperation operation, FableSecureSession session) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (language != null) {
      if (!RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,3}$').hasMatch(language!)) {
        throw ArgumentError('Invalid Accept-Language');
      }
      headers['Accept-Language'] = language!;
    }
    if (platform != null) {
      if (!const {'android', 'ios', 'web', 'desktop'}.contains(platform)) {
        throw ArgumentError('Invalid X-Platform');
      }
      headers['X-Platform'] = platform!;
    }
    if (appVersion != null) {
      if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$').hasMatch(appVersion!)) {
        throw ArgumentError('Invalid X-App-Version');
      }
      headers['X-App-Version'] = appVersion!;
    }
    headers['X-Installation-Id'] = await session.installationId();
    return headers;
  }
}

/// External APIs of ANY technology get NO implicit Fable metadata.
/// Optional public headers are explicit and cannot override auth or HTTP routing.
class ExternalTransportAdapter implements BackendTransportAdapter {
  ExternalTransportAdapter({required this.catalog,
    this.sessionMode = BackendSessionMode.singleBearer,
    Map<String, String> publicHeaders = const {}})
      : publicHeaders = Map.unmodifiable(_validatedHeaders(publicHeaders));

  @override final OperationCatalog catalog;
  @override final BackendSessionMode sessionMode;
  final Map<String, String> publicHeaders;

  static Map<String, String> _validatedHeaders(Map<String, String> headers) {
    if (headers.length > 16) throw ArgumentError('Too many external API headers');
    final clean = <String, String>{};
    const reserved = <String>{
      'authorization', 'cookie', 'set-cookie', 'host', 'origin', 'referer',
      'x-installation-id', 'x-forwarded-for', 'x-forwarded-host', 'forwarded',
      'proxy-authorization', 'content-length', 'transfer-encoding', 'connection',
      'idempotency-key', 'x-csrf-token', 'content-type',
    };
    for (final entry in headers.entries) {
      final key = entry.key;
      final lower = key.toLowerCase();
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$').hasMatch(key) ||
          reserved.contains(lower) || RegExp(r'(auth|token|secret|session|api.key|credential|password)',caseSensitive:false).hasMatch(lower) || clean.keys.any((x) => x.toLowerCase() == lower)) {
        throw ArgumentError('Unsafe or duplicate external header name: $key');
      }
      final value = entry.value;
      if (value.length > 512 || value.contains(RegExp(r'[\r\n\x00-\x1f\x7f]'))) {
        throw ArgumentError('Unsafe external header value');
      }
      clean[key] = value;
    }
    return clean;
  }

  @override Future<Map<String, String>> headersFor(FableOperation operation, FableSecureSession session) async =>
      <String, String>{'Accept': 'application/json', ...publicHeaders};
}
