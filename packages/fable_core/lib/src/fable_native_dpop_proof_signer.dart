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
 * RC188: Fable mobile DPoP is enabled by default; no paid provider or
 * external API key is needed. The native P-256 private key stays hardware-held.
 *
 * A release build MUST have independently pinned the exact Fable contract SHA
 * and HTTPS Backend origin (supplied by the trusted project build workflow).
 * Missing, stale or fixture pins FAIL CLOSED: never downgrade to Bearer.
 * Only non-release development/fixture tests may run without the signer.
 * Other Backend and browser-only clients are not silently enrolled.
 */
FableDpopProofSigner? resolveFableDpopProofSigner(
  Uri baseUri,
  OperationCatalog catalog,
  FableDpopProofSigner? explicitlyProvided,
) {
  // Other Backend NEVER receives Fable's DPoP signer, even when an adapter,
  // user-supplied injection or global build flag tries to enable it.
  if (catalog is! FableContract) {
    if (explicitlyProvided != null) {
      throw ArgumentError('Fable DPoP is forbidden for Other Backend');
    }
    return null;
  }
  // Fable Web uses an independent cookie/CSRF transport.
  if (kIsWeb) {
    if (explicitlyProvided != null) {
      throw ArgumentError('Native DPoP cannot be injected into Web');
    }
    return null;
  }

  // Explicit mock signers remain usable in non-release Flutter unit tests.
  if (explicitlyProvided != null && !kReleaseMode) return explicitlyProvided;

  const enabled = bool.fromEnvironment('FABLE_DPOP_NATIVE_ENABLED',
    defaultValue: true);
  if (!enabled) {
    if (kReleaseMode) {
      throw StateError('Fable DPoP cannot be disabled in a release build');
    }
    return null; // Explicit local test/dev exception ONLY.
  }

  const expectedHash = String.fromEnvironment(
    'FABLE_DPOP_BACKEND_CONTRACT_HASH');
  const expectedOrigin = String.fromEnvironment(
    'FABLE_DPOP_BACKEND_ORIGIN');
  final correctlyPinned =
      RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) &&
      expectedHash == catalog.contractHash &&
      catalog.selectionMode == 'explicit' &&
      catalog.isFeatureAvailable('auth') &&
      catalog.projectName != 'fable-test' &&
      catalog.projectName != 'test-project' &&
      expectedOrigin.isNotEmpty &&
      baseUri.origin == expectedOrigin &&
      baseUri.scheme == 'https';

  if (!correctlyPinned) {
    if (kReleaseMode) {
      throw StateError('DPoP requires a verified non-fixture Fable project pin');
    }
    return null; // Unpinned development fixtures cannot sign unknown hosts.
  }
  // Release may only use the verified hardware-backed platform signer.
  if (kReleaseMode && explicitlyProvided != null &&
      explicitlyProvided is! FableNativeDpopProofSigner) {
    throw StateError('Fable release requires native hardware DPoP signing');
  }
  return explicitlyProvided ?? FableNativeDpopProofSigner(serverOrigin: baseUri);
}
