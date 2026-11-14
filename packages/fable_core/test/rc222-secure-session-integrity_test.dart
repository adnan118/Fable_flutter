import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// Strict in-memory secure-storage fake. Uses noSuchMethod so test fixtures
/// remain compatible across platform-options of FlutterSecureStorage v11+.
class _ControlledStorage implements FlutterSecureStorage {
  final values=<String,String>{};
  String? failWriteKey;
  String? failDeleteKey;
  String? pauseWriteKey;
  Completer<void>? writeReached;
  Completer<void>? releaseWrite;
  final operations=<String>[];

  Future<void> _write(String key,String value) async {
    operations.add('write:'+key);
    if(key==failWriteKey)throw StateError('test-write-failure');
    if(key==pauseWriteKey){
      if(writeReached!=null && !writeReached!.isCompleted)writeReached!.complete();
      await releaseWrite?.future;
    }
    values[key]=value;
  }
  Future<void> _delete(String key) async {
    operations.add('delete:'+key);
    if(key==failDeleteKey)throw StateError('test-delete-failure');
    values.remove(key);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key=invocation.namedArguments[#key] as String?;
    if(invocation.memberName==#read)
      return Future<String?>.value(values[key]);
    if(invocation.memberName==#write)
      return _write(key!,invocation.namedArguments[#value] as String);
    if(invocation.memberName==#delete)
      return _delete(key!);
    throw UnsupportedError('Unexpected FlutterSecureStorage method in test');
  }
}

void main() {
  test('RC222 successful login commits marker before announcing new identity',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.login.success');
    final revision=session.identityRevision;
    final events=<FableIdentityEvent>[];
    final sub=session.identityEvents.listen(events.add);
    addTearDown(sub.cancel);
    expect(await session.replaceTokensIfIdentity(
      expectedIdentity:revision,accessToken:'access-A',refreshToken:'refresh-A'),true);
    expect(session.identityRevision,revision+1);
    expect(await session.accessToken,'access-A');
    expect(await session.refreshToken,'refresh-A');
    expect(storage.values['rc222.login.success.session.integrity'],'ready');
    expect(storage.operations.last,'write:rc222.login.success.session.integrity');
    expect(events.last.authenticated,true);
  });

  test('RC222 account epoch and credential read wait until both native keys commit',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.locked.read');
    storage.pauseWriteKey='rc222.locked.read.session.refresh';
    storage.writeReached=Completer<void>();
    storage.releaseWrite=Completer<void>();
    final prior=session.identityRevision;
    final pending=session.replaceTokensIfIdentity(expectedIdentity:prior,
      accessToken:'new-access',refreshToken:'new-refresh');
    await storage.writeReached!.future;
    expect(session.identityRevision,prior,
      reason:'No identity may be announced while refresh secure storage is pending');
    // This reader must wait behind the namespace lock, never see
    // new access paired with an older refresh while commit is incomplete.
    final accessRead=session.accessToken;
    storage.releaseWrite!.complete();
    expect(await pending,true);
    expect(await accessRead,'new-access');
    expect(await session.refreshToken,'new-refresh');
    expect(session.identityRevision,prior+1);
  });

  test('RC222 failed refresh key write blocks mixed access/refresh secrets',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.refresh.failure');
    await session.replaceTokens(accessToken:'old-access',refreshToken:'old-refresh');
    final revision=session.identityRevision;
    storage.failWriteKey='rc222.refresh.failure.session.refresh';
    await expectLater(session.saveTokensIfIdentity(
      expectedIdentity:revision,accessToken:'new-access',
      refreshToken:'new-refresh',expectedRefreshToken:'old-refresh'),throwsStateError);
    expect(storage.values['rc222.refresh.failure.session.integrity'],'updating');
    expect(await session.accessToken,isNull);
    expect(await session.refreshToken,isNull);
    expect(session.identityRevision,revision+1);
    // No refresh rotation, mutation or old error may accept that stale epoch.
    expect(await session.saveTokensIfIdentity(expectedIdentity:revision,
      accessToken:'stale'),false);
  });

  test('RC222 failed logout delete cannot leave an accepted partial session',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.logout.failure');
    await session.replaceTokens(accessToken:'old-access',refreshToken:'old-refresh');
    storage.failDeleteKey='rc222.logout.failure.session.refresh';
    final revision=session.identityRevision;
    await expectLater(session.clearSessionIfIdentity(revision),throwsStateError);
    expect(session.identityRevision,revision+1);
    expect(storage.values['rc222.logout.failure.session.integrity'],'updating');
    expect(await session.accessToken,isNull);
    expect(await session.refreshToken,isNull);
  });

  test('RC222 recovery requires a complete new credential commit',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.recovery');
    storage.failWriteKey='rc222.recovery.session.refresh';
    await expectLater(session.replaceTokens(
      accessToken:'partial-access',refreshToken:'partial-refresh'),throwsStateError);
    expect(await session.accessToken,isNull);
    storage.failWriteKey=null;
    await session.replaceTokens(accessToken:'fresh-access',refreshToken:'fresh-refresh');
    expect(await session.accessToken,'fresh-access');
    expect(await session.refreshToken,'fresh-refresh');
    expect(storage.values['rc222.recovery.session.integrity'],'ready');
  });

  test('RC222 persisted interrupted marker fails closed after a simulated app restart',()async{
    final storage=_ControlledStorage();
    storage.values.addAll({
      'rc222.afterrestart.session.access':'partial-new',
      'rc222.afterrestart.session.refresh':'old-refresh',
      'rc222.afterrestart.session.integrity':'updating',
    });
    final newlyConstructed=FableSecureSession(storage:storage,namespace:'rc222.afterrestart');
    expect(await newlyConstructed.accessToken,isNull);
    expect(await newlyConstructed.refreshToken,isNull);
    await newlyConstructed.clearSession();
    expect(await newlyConstructed.accessToken,isNull);
    expect(storage.values['rc222.afterrestart.session.integrity'],'ready');
  });

  test('RC222 legacy credentials are read until a complete safe migration write',()async{
    final storage=_ControlledStorage();
    storage.values.addAll({
      'rc222.legacy.session.access':'legacy-access',
      'rc222.legacy.session.refresh':'legacy-refresh',
    });
    final session=FableSecureSession(storage:storage,namespace:'rc222.legacy');
    expect(await session.accessToken,'legacy-access');
    final revision=session.identityRevision;
    expect(await session.saveTokensIfIdentity(expectedIdentity:revision,
      accessToken:'updated-access',expectedRefreshToken:'legacy-refresh'),true);
    expect(await session.accessToken,'updated-access');
    expect(await session.refreshToken,'legacy-refresh');
    expect(storage.values['rc222.legacy.session.integrity'],'ready');
    expect(session.identityRevision,revision);
  });

  test('RC222 failure in one project namespace does not block another',()async{
    final storage=_ControlledStorage();
    final a=FableSecureSession(storage:storage,namespace:'rc222.scope.a');
    final b=FableSecureSession(storage:storage,namespace:'rc222.scope.b');
    await b.replaceTokens(accessToken:'account-b',refreshToken:'refresh-b');
    storage.failWriteKey='rc222.scope.a.session.refresh';
    await expectLater(a.replaceTokens(accessToken:'a',refreshToken:'ar'),throwsStateError);
    expect(await a.accessToken,isNull);
    expect(await b.accessToken,'account-b');
    expect(await b.refreshToken,'refresh-b');
  });

  test('RC222 failed first integrity write never starts mutating access',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.marker.failure');
    storage.failWriteKey='rc222.marker.failure.session.integrity';
    await expectLater(session.replaceTokens(
      accessToken:'attempt',refreshToken:'attempt-r'),throwsStateError);
    expect(storage.operations,[
      'write:rc222.marker.failure.session.integrity',
    ]);
    expect(await session.accessToken,isNull);
  });

  test('RC222 clear success removes both keys and leaves a valid empty marker',()async{
    final storage=_ControlledStorage();
    final session=FableSecureSession(storage:storage,namespace:'rc222.clear.success');
    await session.replaceTokens(accessToken:'a',refreshToken:'r');
    final before=session.identityRevision;
    expect(await session.clearSessionIfIdentity(before),true);
    expect(session.identityRevision,before+1);
    expect(await session.accessToken,isNull);
    expect(await session.refreshToken,isNull);
    expect(storage.values['rc222.clear.success.session.integrity'],'ready');
  });
}
