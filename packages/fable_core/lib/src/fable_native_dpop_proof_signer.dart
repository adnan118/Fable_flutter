import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fable_dpop_proof_signer.dart';
import 'fable_contract.dart';

/// RC166: a platform-backed signer. The P-256 private key never enters Dart.
///
/// Android uses AndroidKeyStore with hardware-backed EC keys. iOS uses Secure
/// Enclave. On unsupported devices (including most simulators), the platform
/// refuses to sign; there is intentionally no software-key fallback.
///
/// Wire this into FableAuthGateway only after the matching Backend contract
/// and session migration are accepted. Do not activate with RC155 Render.
final class FableNativeDpopProofSigner implements FableDpopProofSigner {
  FableNativeDpopProofSigner({
    required Uri serverOrigin,
    MethodChannel? channel,
  }) : _origin = _validateOrigin(serverOrigin),
       _channel = channel ?? const MethodChannel('fable/dpop_native_v1');

  final Uri _origin;
  final MethodChannel _channel;

  static Uri _validateOrigin(Uri uri) {
    if (uri.scheme != 'https' || !uri.hasAuthority || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('DPoP server origin must be a bare HTTPS origin');
    }
    return Uri.parse(uri.origin);
  }

  static final RegExp _access = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _part = RegExp(r'^[A-Za-z0-9_-]+$');

  @override
  Future<String> signProof({
    required String method,
    required Uri htu,
    String? accessToken,
  }) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError('Native hardware DPoP signing is unavailable');
    }
    if (!const <String>{'GET','HEAD','POST','PUT','PATCH','DELETE'}
        .contains(method) || htu.scheme != 'https' ||
        htu.origin != _origin.origin || htu.userInfo.isNotEmpty ||
        htu.hasQuery || htu.hasFragment || !htu.path.startsWith('/') ||
        htu.toString().length > 2048 ||
        (accessToken != null &&
          (accessToken.length < 32 || accessToken.length > 4096 ||
            !_access.hasMatch(accessToken)))) {
      throw ArgumentError('Invalid DPoP signing request');
    }
    // No key or token is logged. Only a compact signed proof crosses back.
    final signed = await _channel.invokeMethod<String>('sign', {
      'method': method,
      'htu': htu.toString(),
      'origin': _origin.origin,
      if (accessToken != null) 'accessToken': accessToken,
    });
    if (signed == null || signed.length < 100 || signed.length > 4096) {
      throw StateError('Native hardware proof was not returned');
    }
    final parts = signed.split('.');
    if (parts.length != 3 || parts.any((p) => !_part.hasMatch(p))) {
      throw StateError('Native hardware proof was malformed');
    }
    return signed;
  }
}

/**
 * RC166 opt-in is intentionally compile-time pinned to BOTH a real backend
 * contract hash and its HTTPS origin. This prevents fixture imports or an
 * Other Backend from silently enabling sender-constrained authentication.
 *
 * Production rollout must be coordinated with Backend RC165, real native
 * private key availability, server schema migration and forced re-login.
 */
FableDpopProofSigner? resolveFableDpopProofSigner(
  Uri baseUri,
  OperationCatalog catalog,
  FableDpopProofSigner? explicitlyProvided,
) {
  if (explicitlyProvided != null) return explicitlyProvided;
  const enabled = bool.fromEnvironment('FABLE_DPOP_NATIVE_ENABLED',
    defaultValue: false);
  if (!enabled || catalog is! FableContract) return null;

  const expectedHash = String.fromEnvironment(
    'FABLE_DPOP_BACKEND_CONTRACT_HASH');
  const expectedOrigin = String.fromEnvironment(
    'FABLE_DPOP_BACKEND_ORIGIN');
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
      expectedHash != catalog.contractHash ||
      catalog.selectionMode != 'explicit' ||
      !catalog.isFeatureAvailable('auth') ||
      catalog.projectName == 'fable-test' ||
      catalog.projectName == 'test-project' ||
      expectedOrigin.isEmpty ||
      baseUri.origin != expectedOrigin) {
    throw StateError('DPoP requires a verified non-fixture Fable project pin');
  }
  return FableNativeDpopProofSigner(serverOrigin: baseUri);
}
