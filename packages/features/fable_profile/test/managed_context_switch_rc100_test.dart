import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';

const entityA='550e8400-e29b-41d4-a716-446655440001';
const entityB='550e8400-e29b-41d4-a716-446655440002';

class _Session extends FableSecureSession {
  _Session(String ns):super(namespace:ns);
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'mock-bearer';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}
FableContract _catalog()=>FableContract(
 contractHash:'rc100',projectName:'account-context-test',
 selectionMode:'advisory',featureIds:const {'managed-accounts'},operations:const {
  'business.read':FableOperation('business.read','GET','/business/me','rc100',
    enforceAuth:true),
 });
class _ControlledApi {
  final pending=<Completer<Response<dynamic>>>[];
  final seen=<RequestOptions>[];
  Dio dio() {
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h)async{
      seen.add(r);
      final future=Completer<Response<dynamic>>();
      pending.add(future);
      h.resolve(await future.future);
    }));
    return dio;
  }
  void answer(int i, Object data,{int statusCode=200}) => pending[i].complete(Response<dynamic>(
    requestOptions:seen[i],statusCode:statusCode,data:data));
  Future<void> waitFor(int count) async {
    for(var attempt=0;attempt<200;attempt++){
      if(pending.length>=count)return;
      await Future<void>.delayed(const Duration(milliseconds:10));
    }
    throw StateError('Simulated Backend did not receive the expected request');
  }
}
FableManagedAccountSelection _choice(String id)=>FableManagedAccountSelection(
 id:id,access:'MANAGER',nameAr:'كيان',nameEn:'Entity',identityRevision:0);

void main(){
  test('RC100 ignores entity A response after switching same-login account to B',()async{
    final session=_Session('rc100.switch.ab'),wire=_ControlledApi(),catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,secureSession:session,client:wire.dio());
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend('rc100|https://api.example.test');
    store.activate(_choice(entityA));
    final old=repo.executeUsingStore(store,'business.read');
    await wire.waitFor(1);
    expect(wire.seen.length,1);
    expect(wire.seen.single.headers['X-Fable-Managed-Entity-Id'],entityA);

    store.activate(_choice(entityB));
    wire.answer(0,{'entity':entityA,'grants':['admin.all']});
    await expectLater(old,throwsA(isA<FableApiException>()));

    final current=repo.executeUsingStore(store,'business.read');
    await wire.waitFor(2);
    expect(wire.seen.length,2);
    expect(wire.seen.last.headers['X-Fable-Managed-Entity-Id'],entityB);
    wire.answer(1,{'entity':entityB,'grants':['read']});
    expect(await current,{'entity':entityB,'grants':['read']});
  });

  test('RC100 A→B→A still rejects response from first A generation',()async{
    final session=_Session('rc100.switch.aba'),wire=_ControlledApi(),catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,secureSession:session,client:wire.dio());
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend('rc100|https://api.example.test');
    final first=_choice(entityA);
    store.activate(first);
    final repo=FableManagedAccountsRepository(gateway,catalog);
    final old=repo.executeUsingStore(store,'business.read');
    await wire.waitFor(1);
    store.activate(_choice(entityB));
    store.activate(first);
    wire.answer(0,{'entity':entityA});
    await expectLater(old,throwsA(isA<FableApiException>()));
    expect(store.selected?.id,entityA);
  });

  test('RC100 role revocation clears in-flight context and discards answer',()async{
    final session=_Session('rc100.revoke'),wire=_ControlledApi(),catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,secureSession:session,client:wire.dio());
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend('rc100|https://api.example.test');
    store.activate(_choice(entityA));
    final request=FableManagedAccountsRepository(gateway,catalog)
      .executeUsingStore(store,'business.read');
    await wire.waitFor(1);
    store.clear();
    wire.answer(0,{'entity':entityA});
    await expectLater(request,throwsA(isA<FableApiException>()));
    expect(store.selected,isNull);
  });

  test('RC100 refuses context stores not bound to same Auth credentials',()async{
    final session=_Session('rc100.correct'),foreign=_Session('rc100.foreign'),
      catalog=_catalog(),wire=_ControlledApi();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,secureSession:session,client:wire.dio());
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:foreign);
    addTearDown(store.dispose);
    store.bindBackend('rc100|https://api.example.test');
    store.activate(_choice(entityA));
    await expectLater(FableManagedAccountsRepository(gateway,catalog)
      .executeUsingStore(store,'business.read'),throwsStateError);
    expect(wire.seen,isEmpty);
  });
  test('RC101 clears selected entity after a scoped authorization denial',()async{
    final session=_Session('rc101.scoped.denial'),wire=_ControlledApi(),catalog=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,secureSession:session,client:wire.dio());
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend('rc100|https://api.example.test');
    store.activate(_choice(entityA));
    final request=FableManagedAccountsRepository(gateway,catalog)
      .executeUsingStore(store,'business.read');
    await wire.waitFor(1);
    wire.answer(0,{'error':'ACCESS_DENIED'},statusCode:403);
    await expectLater(request,throwsA(isA<FableApiException>()));
    expect(store.selected,isNull);
  });

}
