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
