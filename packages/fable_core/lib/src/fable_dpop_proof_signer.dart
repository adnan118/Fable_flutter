/// Fable-only DPoP signing port for non-exportable device P-256 keys.
///
/// The implementation MUST generate/store its private key in the platform's
/// Android Keystore or iOS Keychain/Secure Enclave when available, rotate the
/// proof jti per HTTP attempt, sign ES256, and bind resource proof ath to the
/// exact access token. The private key must never be returned to Dart.
///
/// This interface deliberately does not provide a software-key fallback.
abstract interface class FableDpopProofSigner {
  Future<String> signProof({
    required String method,
    required Uri htu,
    String? accessToken,
  });
}
