import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _PublicOperations implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id == 'public.health';
  @override FableOperation require(String id) =>
      const FableOperation('public.health','GET','/health','hash',
        requiresAuth: false, enforceAuth: true);
}

void main() {
  test('Reject ambient Authorization in injected Dio BaseOptions', () {
    expect(() => UnifiedApiClient(baseUri: Uri.parse('https://example.test'),
      contract: _PublicOperations(), session: FableSecureSession(),
      client: Dio(BaseOptions(headers: <String,dynamic>{'Authorization':'Bearer SECRET'}))),
      throwsArgumentError);
  });
  test('Reject ambient Cookie in injected Dio BaseOptions', () {
    expect(() => UnifiedApiClient(baseUri: Uri.parse('https://example.test'),
      contract: _PublicOperations(), session: FableSecureSession(),
      client: Dio(BaseOptions(headers: <String,dynamic>{'cookie':'SECRET'}))),
      throwsArgumentError);
  });
}
