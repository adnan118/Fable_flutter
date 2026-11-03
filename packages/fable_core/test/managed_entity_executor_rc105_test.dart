import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const a='550e8400-e29b-41d4-a716-446655440001';
const b='550e8400-e29b-41d4-a716-446655440002';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc105.simulated.scoped');
  @override int identityRevision=0;
  final tokenRequested=Completer<void>();
  Completer<void>? tokenGate;
  @override Future<String?> get accessToken async {
    if(!tokenRequested.isCompleted)tokenRequested.complete();
    if(tokenGate!=null)await tokenGate!.future;
    return 'mock-token';
  }
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId() async=>'0123456789abcdef0123456789abcdef';
}

FableContract _contract()=>const FableContract(
  contractHash:'rc105-source-only',
  projectName:'rc105-tests',
  selectionMode:'advisory',
  featureIds:{'managed-accounts'},
  operations:{
    'entity.notes.list':FableOperation('entity.notes.list','GET',
      '/managed-entities/notes','rc105-source-only',enforceAuth:true),
    'entity.notes.update':FableOperation('entity.notes.update','POST',
      '/managed-entities/notes','rc105-source-only',enforceAuth:true),
    'auth.global':FableOperation('auth.global','GET',
      '/auth/sessions','rc105-source-only',enforceAuth:true),
  },
);
FableManagedEntitySelection _choice(String id)=>FableManagedEntitySelection(
  id:id,access:'MANAGER',nameAr:'كيان',nameEn:'Entity',identityRevision:0);

class _SimulatedBackend {
  _SimulatedBackend({this.hold=false,this.status=200}){
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
      requests.add(request);
      if(hold){
        held=Completer<Response<dynamic>>();
        if(!arrived.isCompleted)arrived.complete();
        handler.resolve(await held!.future);
      }else{
        handler.resolve(reply(request));
      }
    }));
  }
  final Dio dio=Dio();
  final bool hold;
  final int status;
  final requests=<RequestOptions>[];
  final arrived=Completer<void>();
  Completer<Response<dynamic>>? held;
  Response<dynamic> reply(RequestOptions request,{int? code})=>
    Response<dynamic>(requestOptions:request,statusCode:code??status,
      data:(code??status)==403?{'errorCode':'access_denied'}:{'ok':true});
  void release({int? code}){
    held!.complete(reply(requests.last,code:code));
  }
}

void main(){
  test('RC105 A denial arriving after selecting B never clears B',()async{
    final backend=_SimulatedBackend(hold:true,status:403);
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    final pending=FableManagedEntityExecutor(gateway,store)
      .execute('entity.notes.list');
    await backend.arrived.future;
    store.activate(_choice(b));
    backend.release(code:403);
    await expectLater(pending,throwsA(isA<FableApiException>().having(
      (e)=>e.code,'code','managed_entity_context_changed_discard_response')));
    expect(store.selected?.id,b);
    expect(backend.requests.single.headers['X-Fable-Managed-Entity-Id'],a);
  });

  test('RC105 A→B→A still discards late response by revision',()async{
    final backend=_SimulatedBackend(hold:true);
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    final pending=FableManagedEntityExecutor(gateway,store)
      .execute('entity.notes.list');
    await backend.arrived.future;
    store.activate(_choice(b));
    store.activate(_choice(a));
    backend.release();
    await expectLater(pending,throwsA(isA<FableApiException>().having(
      (e)=>e.code,'code','managed_entity_context_changed_discard_response')));
    expect(store.selected?.id,a);
  });

  test('RC105 switch during credential await prevents any scoped POST',()async{
    final backend=_SimulatedBackend();
    final session=_Session();
    session.tokenGate=Completer<void>();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    final pending=FableManagedEntityExecutor(gateway,store)
      .execute('entity.notes.update',body:{'text':'simulated'});
    await session.tokenRequested.future;
    store.activate(_choice(b));
    session.tokenGate!.complete();
    await expectLater(pending,throwsA(isA<FableApiException>().having(
      (e)=>e.code,'code','managed_entity_context_changed_discard_response')));
    expect(backend.requests,isEmpty);
    expect(store.selected?.id,b);
  });

  test('RC105 current-context 403 clears only its own selected entity',()async{
    final backend=_SimulatedBackend(status:403);
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    await expectLater(
      FableManagedEntityExecutor(gateway,store).execute('entity.notes.list'),
      throwsA(isA<FableApiException>().having((e)=>e.status,'status',403)));
    expect(store.selected,isNull);
  });

  test('RC105 valid context submits one operation with explicit entity header',()async{
    final backend=_SimulatedBackend();
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    final result=await FableManagedEntityExecutor(gateway,store)
      .execute('entity.notes.update',body:{'text':'test'});
    expect(result,{'ok':true});
    expect(backend.requests.length,1);
    expect(backend.requests.single.headers['X-Fable-Managed-Entity-Id'],a);
  });

  test('RC105 scoped executor rejects wrong session and unrelated Auth routes',()async{
    final backend=_SimulatedBackend();
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    final store=FableManagedEntityStore(session:FableSecureSession(namespace:'other.backend'));
    store.bindBackend(gateway.managedEntityBackendIdentity);
    store.activate(_choice(a));
    addTearDown((){store.dispose();gateway.dispose();});
    await expectLater(FableManagedEntityExecutor(gateway,store)
      .execute('entity.notes.list'),throwsStateError);
    expect(backend.requests,isEmpty);
    final correctlyBound=FableManagedEntityStore(session:session);
    correctlyBound.bindBackend(gateway.managedEntityBackendIdentity);
    correctlyBound.activate(_choice(a));
    addTearDown(correctlyBound.dispose);
    await expectLater(FableManagedEntityExecutor(gateway,correctlyBound)
      .execute('auth.global'),throwsArgumentError);
    expect(backend.requests,isEmpty);
  });
}
