import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';

const a='550e8400-e29b-41d4-a716-446655440001';
const b='550e8400-e29b-41d4-a716-446655440002';
const backendUri='https://api.example.test';

class _Session extends FableSecureSession {
  _Session(String name):super(namespace:name);
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'mock-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}

FableContract _contract()=>FableContract(
  contractHash:'rc105-source',projectName:'scoped-feature',
  selectionMode:'advisory',featureIds:const {'managed-accounts'},operations:const {
    'business.dashboard':FableOperation('business.dashboard','GET',
      '/business/dashboard','rc105-source',enforceAuth:true),
    'business.write':FableOperation('business.write','PATCH',
      '/business/records/{id}','rc105-source',enforceAuth:true),
    'auth.me':FableOperation('auth.me','GET',
      '/auth/me','rc105-source',enforceAuth:true),
    'global.permissions':FableOperation('global.permissions','GET',
      '/permissions/me','rc105-source',enforceAuth:true),
    'admin.read':FableOperation('admin.read','GET',
      '/admin/reports','rc105-source',enforceAuth:true),
    'public.page':FableOperation('public.page','GET',
      '/public/page','rc105-source',requiresAuth:false),
  },
);
const scoped=FableManagedScopedOperation(operationId:'business.dashboard',
  method:'GET',path:'/business/dashboard',contractHash:'rc105-source');
FableManagedAccountSelection _selection(String id)=>
  FableManagedAccountSelection(id:id,access:'MANAGER',
    nameAr:'كيان',nameEn:'Entity',identityRevision:0);
class _Wire {
  final seen=<RequestOptions>[];
  final waiting=<Completer<Response<dynamic>>>[];
  Dio get dio {
    final client=Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
      seen.add(request);
      final pending=Completer<Response<dynamic>>();
      waiting.add(pending);
      handler.resolve(await pending.future);
    }));
    return client;
  }
  Future<void> expectCount(int n)async{
    for(var attempt=0;attempt<200;attempt++){
      if(seen.length>=n)return;
      await Future<void>.delayed(const Duration(milliseconds:10));
    }
    throw StateError('Mock Backend did not receive $n requests');
  }
  void complete(int i,Object data,{int statusCode=200}){
    waiting[i].complete(Response<dynamic>(requestOptions:seen[i],
      statusCode:statusCode,data:data));
  }
}

void main(){
  test('RC105 rejects unknown, stale, public, Auth, Admin or global permission binding',(){
    final contract=_contract();
    scoped.validate(contract);
    const invalid=[
      FableManagedScopedOperation(operationId:'business.dashboard',
        method:'POST',path:'/business/dashboard',contractHash:'rc105-source'),
      FableManagedScopedOperation(operationId:'business.dashboard',
        method:'GET',path:'/business/dashboard',contractHash:'old-project'),
      FableManagedScopedOperation(operationId:'unknown',
        method:'GET',path:'/business/dashboard',contractHash:'rc105-source'),
      FableManagedScopedOperation(operationId:'auth.me',
        method:'GET',path:'/auth/me',contractHash:'rc105-source'),
      FableManagedScopedOperation(operationId:'global.permissions',
        method:'GET',path:'/permissions/me',contractHash:'rc105-source'),
      FableManagedScopedOperation(operationId:'admin.read',
        method:'GET',path:'/admin/reports',contractHash:'rc105-source'),
      FableManagedScopedOperation(operationId:'public.page',
        method:'GET',path:'/public/page',contractHash:'rc105-source'),
    ];
    for(final binding in invalid){
      expect(()=>binding.validate(contract),throwsA(isA<Object>()));
    }
  });
  test('RC105 sends scope header only on explicitly bound Backend operation',()async{
    final session=_Session('rc105.same'),catalog=_contract(),wire=_Wire();
    final gateway=FableAuthGateway(baseUri:Uri.parse(backendUri),
      contract:catalog,secureSession:session,client:wire.dio);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_selection(a));
    final repo=FableManagedAccountsRepository(gateway,catalog);
    final request=repo.executeBoundInStore(store,scoped);
    await wire.expectCount(1);
    expect(wire.seen.single.path,'/business/dashboard');
    expect(wire.seen.single.headers['X-Fable-Managed-Entity-Id'],a);
    wire.complete(0,{'verified':true});
    expect(await request,{'verified':true});
  });
  test('RC105 discards A response after A→B→A even when original A object is restored',()async{
    final session=_Session('rc105.switch'),catalog=_contract(),wire=_Wire();
    final gateway=FableAuthGateway(baseUri:Uri.parse(backendUri),
      contract:catalog,secureSession:session,client:wire.dio);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    addTearDown(store.dispose);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    final first=_selection(a);
    store.activate(first);
    final old=FableManagedAccountsRepository(gateway,catalog)
      .executeBoundInStore(store,scoped);
    await wire.expectCount(1);
    store.activate(_selection(b));
    store.activate(first);
    wire.complete(0,{'memberRecords':['A']});
    await expectLater(old,throwsA(isA<FableApiException>()));
  });
  test('RC105 no request with foreign identity namespace or contract binding',()async{
    final session=_Session('rc105.current'),other=_Session('rc105.foreign'),
      catalog=_contract(),wire=_Wire();
    final gateway=FableAuthGateway(baseUri:Uri.parse(backendUri),
      contract:catalog,secureSession:session,client:wire.dio);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:other);
    addTearDown(store.dispose);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_selection(a));
    final repo=FableManagedAccountsRepository(gateway,catalog);
    await expectLater(repo.executeBoundInStore(store,scoped),throwsStateError);
    expect(wire.seen,isEmpty);
  });
}
