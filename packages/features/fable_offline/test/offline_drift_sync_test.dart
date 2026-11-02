import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_offline/fable_offline.dart';

class VerifiedContext implements FableVerifiedSyncContext {
  VerifiedContext(this.scope);
  String? scope;
  bool online=true;
  @override Future<String?> verifiedScope()async=>scope;
  @override Future<bool> networkAvailable()async=>online;
}
class FakeExecutor implements FableOfflineCommandExecutor {
  FakeExecutor(this.response);
  FableSyncAck response;
  final keys=<String>[];
  @override Future<FableSyncAck> submit(OfflineOutboxRow row,
    {required String idempotencyKey})async{
    keys.add(idempotencyKey);
    return response;
  }
}
const scope='https://api.example.test|project-1|user-1|entity-1';
FableOfflineSyncEngine engine(FableOfflineDriftStore db,VerifiedContext ctx,{
  Iterable<FableOfflineWriteGrant>? grants,
})=>FableOfflineSyncEngine(
  store:db,context:ctx,scope:scope,verifiedBackendContractHash:'verified-hash',
  writeGrants:grants??[const FableOfflineWriteGrant(
    operationId:'social.react',method:'POST',backendContractHash:'verified-hash',
    idempotencyVerified:true,conflictProtocolVerified:true)],
  publicCacheReadOperations:const ['public.posts.get'],
);

void main(){
  test('SQLite/Drift stores bounded cached reads; stale response is explicit',()async{
    final db=FableOfflineDriftStore(NativeDatabase.memory());
    addTearDown(db.close);
    final context=VerifiedContext(scope),sync=engine(db,context);
    await sync.cacheApprovedRead(operationId:'public.posts.get',cacheKey:'feed',
      response:{'value':42},ttl:const Duration(minutes:1));
    expect(await sync.cachedRead(operationId:'public.posts.get',
      cacheKey:'feed'),{'value':42});
    await expectLater(sync.cacheApprovedRead(
      operationId:'public.posts.get',cacheKey:'secret',
      response:{'refreshToken':'never-persist'},ttl:const Duration(days:1)),
      throwsArgumentError);
    await expectLater(sync.cachedRead(operationId:'auth.login',
      cacheKey:'session'),throwsArgumentError);
    context.scope='other-user';
    await expectLater(sync.cachedRead(operationId:'public.posts.get',
      cacheKey:'feed'),throwsStateError);
  });
  test('queue only approved idempotent writes and consumes a real ACK',()async{
    final db=FableOfflineDriftStore(NativeDatabase.memory());
    addTearDown(db.close);
    final context=VerifiedContext(scope),sync=engine(db,context);
    await expectLater(sync.enqueueApprovedWrite(operationId:'social.react',
      resourceId:'post1',body:{'liked':true}),throwsArgumentError);
    final id=await sync.enqueueApprovedWrite(operationId:'social.react',
      resourceId:'post1',body:{'liked':true},baseVersion:'rev1');
    expect(id.length,43);
    expect(await sync.pendingCount,1);
    final remote=FakeExecutor(const FableSyncAck(
      FableSyncDisposition.acknowledged,serverVersion:'rev2'));
    expect(await sync.flush(remote),1);
    expect(remote.keys,[id]);
    expect(await sync.pendingCount,0);
  });
  test('unknown outcome retries same idempotency ID; no false ack',()async{
    final db=FableOfflineDriftStore(NativeDatabase.memory());
    addTearDown(db.close);
    final context=VerifiedContext(scope),sync=engine(db,context);
    final id=await sync.enqueueApprovedWrite(operationId:'social.react',
      resourceId:'post1',body:{'liked':true},baseVersion:'rev1');
    final remote=FakeExecutor(const FableSyncAck(FableSyncDisposition.retryLater));
    expect(await sync.flush(remote),0);
    expect(await sync.pendingCount,1);
    final stillPending=await db.pending(scope:scope,includeRetryDelay:true);
    expect(stillPending.single.id,id);
    expect(stillPending.single.attempts,1);
    expect(await db.pending(scope:scope),isEmpty);
    expect(remote.keys,[id]);
  });
  test('conflict suspends replay; logout clears only verified scope',()async{
    final db=FableOfflineDriftStore(NativeDatabase.memory());
    addTearDown(db.close);
    final context=VerifiedContext(scope),sync=engine(db,context);
    await sync.enqueueApprovedWrite(operationId:'social.react',
      resourceId:'post1',body:{'liked':true},baseVersion:'rev1');
    final remote=FakeExecutor(const FableSyncAck(FableSyncDisposition.conflict));
    expect(await sync.flush(remote),0);
    expect(await sync.pendingCount,1);
    expect(await db.pending(scope:scope),isEmpty);
    context.scope=null;
    await expectLater(sync.enqueueApprovedWrite(operationId:'social.react',
      resourceId:'post2',body:{'liked':true},baseVersion:'rev1'),
      throwsStateError);
    await sync.clearOnConfirmedLogout();
    expect(await sync.pendingCount,0);
  });
  test('deny financial/unsafe or unreviewed mutation contract',()async{
    final db=FableOfflineDriftStore(NativeDatabase.memory());
    addTearDown(db.close);
    final context=VerifiedContext(scope);
    expect(()=>engine(db,context,grants:[
      const FableOfflineWriteGrant(operationId:'booking.confirm',method:'POST',
        backendContractHash:'verified-hash',idempotencyVerified:true,
        conflictProtocolVerified:true)]),throwsArgumentError);
    expect(()=>engine(db,context,grants:[
      const FableOfflineWriteGrant(operationId:'social.react',method:'DELETE',
        backendContractHash:'verified-hash',idempotencyVerified:false,
        conflictProtocolVerified:true)]),throwsArgumentError);
    final sync=engine(db,context);
    await expectLater(sync.enqueueApprovedWrite(operationId:'payment.charge',
      resourceId:'id',body:{'amount':123},baseVersion:'rev1'),
      throwsArgumentError);
    await db.close();
  });
}
