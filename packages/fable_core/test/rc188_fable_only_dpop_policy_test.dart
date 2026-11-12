import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _OtherBackend implements OperationCatalog {
  const _OtherBackend();
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id == 'public.ping';
  @override FableOperation require(String id) =>
      const FableOperation('public.ping', 'GET', '/ping', 'test-hash',
        requiresAuth: false, enforceAuth: true);
}
class _FakeFableSigner implements FableDpopProofSigner {
  @override Future<String> signProof({
    required String method, required Uri htu, String? accessToken,
  }) async => throw StateError('Other Backend must not call Fable DPoP');
}
void main() {
  final origin = Uri.parse('https://other-backend.example');
  test('RC188 Other Backend NEVER auto-enables Fable DPoP', () {
    expect(resolveFableDpopProofSigner(origin, const _OtherBackend(), null),
      isNull);
  });
  test('RC188 Other Backend rejects even an explicit Fable DPoP signer', () {
    expect(() => resolveFableDpopProofSigner(
      origin, const _OtherBackend(), _FakeFableSigner()), throwsArgumentError);
  });
  test('RC188 Other Backend rejects an explicitly injected native signer', () {
    final signer = FableNativeDpopProofSigner(serverOrigin: origin);
    expect(() => resolveFableDpopProofSigner(
      origin, const _OtherBackend(), signer), throwsArgumentError);
  });
  test('RC188 external UnifiedApiClient never accepts a Fable proof signer', () {
    expect(() => UnifiedApiClient(
      baseUri: origin,
      contract: const _OtherBackend(),
      session: FableSecureSession(namespace: 'rc188.other-backend-test'),
      dpopProofSigner: _FakeFableSigner(),
    ), throwsArgumentError);
  });
}
