import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const _hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _operationHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
FableContract _contract() => FableContract(
  contractHash: _hash,
  operations: const <String, FableOperation>{
    'notes.create': FableOperation('notes.create', 'POST', '/notes',
      _operationHash, requiresAuth: true, enforceAuth: true,
      requiresIdempotency: true),
    'notes.public-create': FableOperation('notes.public-create', 'POST', '/public-notes',
      _operationHash, requiresAuth: false, enforceAuth: true,
      requiresIdempotency: true),
    'notes.legacy-create': FableOperation('notes.legacy-create', 'POST', '/legacy-notes',
      _operationHash, requiresAuth: true, enforceAuth: false,
      requiresIdempotency: true),
    'notes.get-idempotent': FableOperation('notes.get-idempotent', 'GET', '/notes',
      _operationHash, requiresAuth: true, enforceAuth: true,
      requiresIdempotency: true),
    'notes.custom-credential': FableOperation('notes.custom-credential', 'POST',
      '/notes/external', _operationHash, requiresAuth: true, enforceAuth: true,
      credentialHeader: 'X-API-Key', requiresIdempotency: true),
    'notes.custom-conditional': FableOperation('notes.custom-conditional', 'PATCH',
      '/notes/external', _operationHash, requiresAuth: true, enforceAuth: true,
      credentialHeader: 'X-API-Key', requiresIfMatch: true),
  },
  featureIds: const <String>{'notes'},
  projectName: 'rc359-source-fixture',
  selectionMode: 'explicit',
);

void main() {
  test('RC359 idempotency requires a signed enforced Bearer mutation', () async {
    final api = UnifiedApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      contract: _contract(),
      session: FableSecureSession(),
    );
    addTearDown(api.dispose);
    for (final operation in <String>[
      'notes.public-create',
      'notes.legacy-create',
      'notes.get-idempotent',
      'notes.custom-credential',
    ]) {
      await expectLater(
        api.request(operation, idempotencyKey: _hash),
        throwsArgumentError,
        reason: operation,
      );
    }
  });

  test('RC359 valid signed mutation still requires explicit idempotency key', () async {
    final api = UnifiedApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      contract: _contract(),
      session: FableSecureSession(),
    );
    addTearDown(api.dispose);
    await expectLater(api.request('notes.create'), throwsArgumentError);
    await expectLater(
      api.request('notes.create', idempotencyKey: 'not-a-sha256-value'),
      throwsArgumentError,
    );
  });

  test('RC359 conditional headers never go to custom credential routes', () async {
    final api = UnifiedApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      contract: _contract(),
      session: FableSecureSession(),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.request('notes.custom-conditional', ifMatch: _hash),
      throwsArgumentError,
    );
  });
}
