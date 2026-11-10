import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc163.managed.contract.gate');
  @override int identityRevision = 0;
  @override Future<String?> get accessToken async => null;
  @override Future<String?> get refreshToken async => null;
  @override Future<String> installationId() async => 'rc163-disposable-installation';
}

FableContract _contract({
  String key = 'managed.list',
  String operationId = 'managed.list',
  String method = 'GET',
  String path = '/managed-entities',
  bool requiresAuth = true,
  bool enforceAuth = true,
  String? credentialHeader,
  bool duplicate = false,
}) => FableContract(
  contractHash: digest,
  projectName: 'rc163-source-only-not-a-live-project',
  selectionMode: 'advisory',
  featureIds: const {'profile'},
  operations: {
    key: FableOperation(operationId, method, path, digest,
      requiresAuth: requiresAuth, enforceAuth: enforceAuth,
      credentialHeader: credentialHeader),
    if (duplicate) 'managed.alias': const FableOperation('managed.alias',
      'GET', '/managed-entities', digest, enforceAuth: true),
  },
);

FableManagedAccountsRepository _repo(FableContract c) =>
  FableManagedAccountsRepository(
    FableAuthGateway(
      baseUri: Uri.parse('https://source-only.invalid'),
      contract: c,
      secureSession: _Session(),
    ), c,
  );

void main() {
  test('RC163 authentic protected managed list retains its declared mapping', () {
    final repo = _repo(_contract());
    expect(repo.canList, isTrue);
    expect(repo.can('/managed-entities', 'POST'), isFalse);
    expect(repo.can('/auth/me/account', 'GET'), isFalse);
  });

  test('RC163 requires actual enforced Bearer policy, not a route-shaped claim', () async {
    for (final c in [
      _contract(requiresAuth: false),
      _contract(enforceAuth: false),
      _contract(credentialHeader: 'X-Provider-Token'),
    ]) {
      final repo = _repo(c);
      expect(repo.canList, isFalse);
      expect(repo.can('/managed-entities', 'GET'), isFalse);
      await expectLater(repo.listMine(), throwsStateError);
    }
  });

  test('RC163 operation catalogue ID must match its actual indexed ID', () async {
    for (final c in [
      _contract(key: 'managed.alias'),
      _contract(operationId: 'forged.list'),
      _contract(duplicate: true),
    ]) {
      final repo = _repo(c);
      expect(repo.canList, isFalse);
      await expectLater(repo.listMine(), throwsStateError);
    }
  });

  test('RC163 wrong HTTP verb or path never enables entity list', () {
    for (final c in [
      _contract(method: 'POST'),
      _contract(method: 'HEAD'),
      _contract(path: '/auth/me/account'),
      _contract(path: '/managed-entities/public'),
    ]) {
      expect(_repo(c).canList, isFalse);
    }
  });

  test('RC163 managed-scoped operations reject unenforced or aliased IDs', () {
    const binding = FableManagedScopedOperation(
      operationId: 'business.read', method: 'GET', path: '/business/me',
      contractHash: digest,
    );
    FableContract business({bool enforce = true, bool alias = false}) =>
      FableContract(
        contractHash: digest, projectName: 'rc163-scoped-source-only',
        selectionMode: 'advisory', featureIds: const {'profile'},
        operations: {
          'business.read': FableOperation(
            alias ? 'forged.read' : 'business.read',
            'GET', '/business/me', digest, enforceAuth: enforce,
          ),
        },
      );
    expect(() => binding.validate(business()), returnsNormally);
    expect(() => binding.validate(business(enforce: false)), throwsStateError);
    expect(() => binding.validate(business(alias: true)), throwsStateError);
  });
}
