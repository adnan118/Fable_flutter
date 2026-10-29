import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';
import 'package:fable_core/fable_core.dart';

class _Credentials extends FableSecureSession {
  _Credentials() : super(namespace: 'fable.access.lifecycle.test');
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
}
