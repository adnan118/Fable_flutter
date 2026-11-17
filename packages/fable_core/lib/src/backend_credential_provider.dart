import 'fable_contract.dart';

/// Runtime-only authentication for backend contracts that use a declared
/// non-Bearer HTTP header (API key, HTTP Basic, or a provider-defined scheme).
///
/// Secrets must originate from an appropriate runtime/OS credential flow,
/// never from a JSON asset, a hardcoded constant, or public client headers.
/// Cookie + CSRF flows need a dedicated implementation, not this header API.
abstract interface class BackendCredentialProvider {
  /// Full header value, e.g. a secret API token or "Basic ..." for
  /// an operation whose contract explicitly declares its credential header.
  Future<String?> credentialFor(FableOperation operation);

  /// Called only after a protected request gets a definitive HTTP 401.
  /// Return true iff the provider has successfully acquired NEW credentials.
  /// Temporary network failures should throw instead of returning false.
  Future<bool> recoverUnauthorized(FableOperation operation);
}


/// A provider credential may use e.g. Authorization (HTTP Basic) or X-API-Key,
/// but must never masquerade as a transport, tenant, replay or proof header.
/// Check this both when importing Other Backend catalogs and at dispatch:
/// a test/host-supplied OperationCatalog can bypass the asset importer.
bool isAllowedExternalCredentialHeader(Object? value) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9-]{0,63}$').hasMatch(value)) {
    return false;
  }
  final header=value.toLowerCase();
  if (header.startsWith('x-fable-')) return false;
  return !const <String>{
    'host','cookie','set-cookie','connection','content-length',
    'transfer-encoding','origin','referer','proxy-authorization',
    'x-forwarded-for','x-forwarded-host','forwarded','x-installation-id',
    'dpop','idempotency-key','if-match','range',
    'x-security-challenge-id','x-csrf-token',
    'accept','accept-language','accept-encoding','content-type',
  }.contains(header);
}
