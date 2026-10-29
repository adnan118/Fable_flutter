import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _TestCatalog implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id == 'public.info' || id == 'private.info';
  @override FableOperation require(String id) {
    if (!supports(id)) throw StateError('Operation not allowed');
    return FableOperation(id, 'GET', '/safe', 'test',
        requiresAuth: id == 'private.info', enforceAuth: true);
  }
}

void main() {
  test('public external operations cannot receive bearer credentials by override', () async {
    final client = FableApiClient(baseUri: Uri.parse('https://api.example.test'),
      contract: _TestCatalog(), session: FableSecureSession());
    addTearDown(client.dispose);
    await expectLater(client.request('public.info', authorized: true), throwsArgumentError);
  });

  test('protected external operations cannot have authorization suppressed', () async {
    final client = FableApiClient(baseUri: Uri.parse('https://api.example.test'),
      contract: _TestCatalog(), session: FableSecureSession());
    addTearDown(client.dispose);
    await expectLater(client.request('private.info', authorized: false), throwsArgumentError);
  });
}
