import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';
import 'package:fable_core/fable_core.dart';

class _Credentials extends FableSecureSession {
  _Credentials({String namespace='fable.access.lifecycle.test'}) : super(namespace: namespace);
  final _identities = StreamController<FableIdentityEvent>.broadcast(sync: true);
  final _denials = StreamController<void>.broadcast(sync: true);
  String? token;
  int revision = 0;

  @override
  int get identityRevision => revision;
  @override
  Future<String?> get accessToken async => token;
  @override
  Stream<FableIdentityEvent> get identityEvents => _identities.stream;
  @override
  Stream<void> get authorizationDenials => _denials.stream;

  void login(String nextToken) {
    token = nextToken;
    revision++;
    _identities.add(FableIdentityEvent(revision, true));
  }
  void logout() {
    token = null;
    revision++;
    _identities.add(FableIdentityEvent(revision, false));
  }
  void deny() => _denials.add(null);
  Future<void> close() async {
    await _identities.close();
    await _denials.close();
  }
}

class _PendingGateway implements BackendApiGateway {
  final requests = <Completer<Response<dynamic>>>[];
  @override
  Future<Response<dynamic>> execute(String operationId, {
    Map<String, dynamic>? path, Map<String, dynamic>? query, Object? body,
    CancelToken? cancelToken, String? ifMatch,
  }) {
    if (operationId != 'identity.permissions') throw StateError('Unexpected operation');
    final pending = Completer<Response<dynamic>>();
    requests.add(pending);
    return pending.future;
  }
  void complete(int index, String user, List<String> keys) {
    requests[index].complete(Response<dynamic>(
      requestOptions: RequestOptions(path: '/rights'), statusCode: 200,
      data: {'subject': user, 'grants': keys, 'groups': <String>[]},
    ));
  }
  @override
  void dispose() {}
}

FableAccessSession _access(_PendingGateway gateway) => FableAccessSession(
  FableAccessRepository(gateway, operationId: 'identity.permissions',
    userIdField: 'subject', permissionsField: 'grants', rolesField: 'groups'));

Future<void> _drain() async => Future<void>.delayed(Duration.zero);

void main() {
  test('login, account switch and late old response never leak previous grants', () async {
    final credentials = _Credentials();
    final gateway = _PendingGateway();
    final access = _access(gateway);
    try {
      await access.bindToCredentials(credentials);
      expect(access.value, isNull);
      credentials.login('token-A');
      expect(gateway.requests.length, 1);
      credentials.login('token-B');
      expect(access.value, isNull);
      // A pending A response MUST NOT delay B's independent permissions request.
      expect(gateway.requests.length, 2);
      gateway.complete(1, 'B', ['projects.read']);
      await _drain();
      expect(access.value!.userId, 'B');
      gateway.complete(0, 'A', ['admin.all']);
      await _drain();
      expect(access.value!.userId, 'B');
      expect(access.value!.keys, ['projects.read']);
      credentials.logout();
      expect(access.value, isNull);
      await access.onForeground();
      expect(gateway.requests.length, 2);
    } finally {
      access.dispose();
      await credentials.close();
    }
  });

  test('403 fails closed immediately, refreshes grant, foreground revalidates', () async {
    final credentials = _Credentials();
    final gateway = _PendingGateway();
    final access = _access(gateway);
    try {
      await access.bindToCredentials(credentials);
      credentials.login('signed-in');
      gateway.complete(0, 'A', ['files.delete']);
      await _drain();
      expect(access.value!.can('files.delete'), true);
      credentials.deny();
      expect(access.value, isNull);
      expect(gateway.requests.length, 2);
      gateway.complete(1, 'A', ['files.read']);
      await _drain();
      expect(access.value!.can('files.delete'), false);
      final foreground = access.onForeground();
      expect(gateway.requests.length, 3);
      gateway.complete(2, 'A', ['files.read']);
      await foreground;
    } finally {
      // The final revalidation may still be outstanding: disposing rejects it.
      access.dispose();
      await credentials.close();
    }
  });

  test('403 during pending snapshot cannot resurrect a stale grant', () async {
    final credentials = _Credentials();
    final gateway = _PendingGateway();
    final access = _access(gateway);
    try {
      await access.bindToCredentials(credentials);
      credentials.login('token-A');
      expect(gateway.requests.length, 1);
      credentials.deny(); // Another request returned 403 mid-snapshot.
      expect(access.value, isNull);
      gateway.complete(0, 'A', ['dangerous.manage']);
      await _drain();
      expect(access.value, isNull);
      // Avoid automatic retry storms if the denied operation was GET rights.
      expect(gateway.requests.length, 1);
      final foreground = access.onForeground();
      expect(gateway.requests.length, 2);
      gateway.complete(1, 'A', ['safe.read']);
      await foreground;
      expect(access.value!.keys, ['safe.read']);
    } finally {
      access.dispose();
      await credentials.close();
    }
  });

  test('account logout while permissions are in flight discards the response', () async {
    final credentials = _Credentials();
    final gateway = _PendingGateway();
    final access = _access(gateway);
    try {
      await access.bindToCredentials(credentials);
      credentials.login('token-A');
      credentials.logout();
      gateway.complete(0, 'A', ['secrets.view']);
      await _drain();
      expect(access.value, isNull);
    } finally {
      access.dispose();
      await credentials.close();
    }
  });
  test('managed selection invalidates grants and discards an earlier snapshot', () async {
    final credentials = _Credentials();
    final gateway = _PendingGateway();
    final store = FableManagedEntityStore(session: credentials);
    store.bindBackend('access-test|https://api.example.test');
    final access = _access(gateway);
    try {
      await access.bindToCredentials(credentials, managedEntityStore: store);
      credentials.login('token-A');
      expect(gateway.requests.length, 1);
      gateway.complete(0, 'A', ['global.read']);
      await _drain();
      expect(access.value!.keys, ['global.read']);

      store.activate(const FableManagedEntitySelection(
        id:'550e8400-e29b-41d4-a716-446655440001',
        access:'MANAGER',nameAr:'Entity A',nameEn:'Entity A',
        identityRevision:1,
      ));
      expect(access.value, isNull);
      expect(gateway.requests.length, 2);

      // Switching again starts a newer snapshot; A's late result cannot win.
      store.activate(const FableManagedEntitySelection(
        id:'550e8400-e29b-41d4-a716-446655440002',
        access:'VIEWER',nameAr:'Entity B',nameEn:'Entity B',
        identityRevision:1,
      ));
      expect(access.value, isNull);
      expect(gateway.requests.length, 3);
      gateway.complete(1, 'A', ['stale.grant']);
      await _drain();
      expect(access.value, isNull);
      gateway.complete(2, 'A', ['global.read']);
      await _drain();
      expect(access.value!.keys, ['global.read']);

      // The global permissions endpoint is re-read, but managed roles are
      // never synthesized into global keys by the Flutter client.
      store.clear();
      expect(access.value, isNull);
      expect(gateway.requests.length, 4);
      gateway.complete(3, 'A', ['global.read']);
      await _drain();
      expect(access.value!.keys, ['global.read']);
    } finally {
      access.dispose();
      store.dispose();
      await credentials.close();
    }
  });

  test('AccessSession rejects a managed store from another Backend identity namespace', () async {
    final credentials = _Credentials();
    final foreign = _Credentials(namespace:'fable.access.foreign.test');
    final gateway = _PendingGateway();
    final store = FableManagedEntityStore(session: foreign);
    store.bindBackend('foreign|https://api.example.test');
    final access = _access(gateway);
    try {
      await expectLater(
        access.bindToCredentials(credentials, managedEntityStore: store),
        throwsStateError,
      );
      expect(gateway.requests, isEmpty);
    } finally {
      access.dispose();
      store.dispose();
      await credentials.close();
      await foreign.close();
    }
  });

}
