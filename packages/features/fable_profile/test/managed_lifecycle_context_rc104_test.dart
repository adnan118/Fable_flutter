import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';
import 'package:fable_profile/src/managed_accounts_page.dart';

const entityA='550e8400-e29b-41d4-a716-446655440001';
const entityB='550e8400-e29b-41d4-a716-446655440002';
const challenge='550e8400-e29b-41d4-a716-446655440010';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc104.owner.lifecycle');
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'mock-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}
FableContract _contract()=>FableContract(
  contractHash:'rc104-contract',projectName:'rc104-test',
  selectionMode:'advisory',featureIds:const {'managed-accounts'},operations:const {
    'managed.list':FableOperation('managed.list','GET',
      '/managed-entities','rc104-contract',enforceAuth:true),
    'managed.invitations':FableOperation('managed.invitations','GET',
      '/managed-entities/invitations/me','rc104-contract',enforceAuth:true),
    'auth.2fa.status':FableOperation('auth.2fa.status','GET',
      '/auth/2fa/status','rc104-contract',enforceAuth:true),
    'auth.otp.request':FableOperation('auth.otp.request','POST',
      '/auth/otp/request','rc104-contract',enforceAuth:true),
    'auth.otp.verify':FableOperation('auth.otp.verify','POST',
      '/auth/otp/verify','rc104-contract',enforceAuth:true),
    'managed.disable':FableOperation('managed.disable','POST',
      '/managed-entities/{id}/disable','rc104-contract',enforceAuth:true),
  },
);
Map<String,Object?> _entity([String access='OWNER'])=>{
  'id':entityA,'type':'hotel','nameAr':'فندق أ','nameEn':'Hotel A',
  'status':'ACTIVE','visibility':'INVITE_ONLY',
  'collaborationEnabled':true,'managersCanInvite':true,
  'memberships':[{'access':access,'active':true}],
};
class _Backend {
  _Backend({this.holdOtpVerify=false}){
    dio.interceptors.add(InterceptorsWrapper(onRequest:(r,h)async{
      requests.add(r);
      if(holdOtpVerify&&r.path=='/auth/otp/verify'){
        verifyPending=Completer<Response<dynamic>>();
        h.resolve(await verifyPending!.future);
        return;
      }
      Object? body;
      switch(r.path){
        case '/managed-entities':
          body=[_entity(currentAccess)];
        case '/managed-entities/invitations/me':
          body=[];
        case '/auth/2fa/status':
          body={'enabled':false};
        case '/auth/otp/request':
          body={'challengeId':challenge};
        case '/auth/otp/verify':
          body={'verified':true,'challengeId':challenge,
            'purpose':'SENSITIVE_ACTION'};
        case '/managed-entities/$entityA/disable':
          body={'status':'DISABLED'};
      }
      h.resolve(Response<dynamic>(requestOptions:r,data:body,statusCode:200));
    }));
  }
  final Dio dio=Dio();
  final List<RequestOptions> requests=[];
  final bool holdOtpVerify;
  Completer<Response<dynamic>>? verifyPending;
  String currentAccess='OWNER';
  Future<void> waitForOtpVerify()async{
    for(var i=0;i<200;i++){
      if(verifyPending!=null)return;
      await Future<void>.delayed(const Duration(milliseconds:10));
    }
    throw StateError('OTP verify was not dispatched to simulated Backend');
  }
  int count(String path)=>requests.where((r)=>r.path==path).length;
}

void main(){
  test('RC104 consumed OTP proof never authorizes a lifecycle POST after context switch',()async{
    final backend=_Backend(holdOtpVerify:true),session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,_contract());
    final entity=FableManagedAccount.fromPayload(_entity());
    final pending=await repo.requestLifecycleChallenge(entity,'disable');
    expect(pending.entityId,entityA);
    var current=true;
    final future=repo.verifyAndApplyLifecycle(pending,'123456',
      contextStillValid:()=>current);
    await backend.waitForOtpVerify();
    current=false; // A changed while verified proof was in flight.
    backend.verifyPending!.complete(Response<dynamic>(
      requestOptions:backend.requests.last,
      statusCode:200,data:{'verified':true,'challengeId':challenge,
        'purpose':'SENSITIVE_ACTION'},
    ));
    await expectLater(future,throwsStateError);
    expect(backend.count('/managed-entities/$entityA/disable'),0);
  });

  test('RC104 valid owner context can submit once after purpose-scoped OTP proof',()async{
    final backend=_Backend(),session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,_contract());
    final pending=await repo.requestLifecycleChallenge(
      FableManagedAccount.fromPayload(_entity()),'disable');
    final changed=await repo.verifyAndApplyLifecycle(pending,'123456',
      contextStillValid:()=>true);
    expect(changed,{'status':'DISABLED'});
    expect(backend.count('/managed-entities/$entityA/disable'),1);
  });

  testWidgets('RC104 selection switch clears owner OTP prompt before verification',
  (tester)async{
    final backend=_Backend(),session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home:FableManagedEntityScope(
      store:store,child:FableManagedAccountsPage(
        gateway:gateway,contract:_contract(),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable entity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification required:'),findsOneWidget);
    store.activate(const FableManagedEntitySelection(
      id:entityB,access:'VIEWER',nameAr:'فندق ب',nameEn:'Hotel B',
      identityRevision:0,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification required:'),findsNothing);
    expect(backend.count('/auth/otp/verify'),0);
    expect(backend.count('/managed-entities/$entityA/disable'),0);
  });

  testWidgets('RC104 foreground downgrade revokes outstanding owner OTP prompt',
  (tester)async{
    final backend=_Backend(),session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:_contract(),secureSession:session,client:backend.dio);
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FableManagedAccountsPage(
      gateway:gateway,contract:_contract(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable entity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification required:'),findsOneWidget);
    backend.currentAccess='VIEWER';
    // Flutter permits inactive → resumed, but not paused → resumed directly.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification required:'),findsNothing);
    expect(backend.count('/auth/otp/verify'),0);
    expect(backend.count('/managed-entities/$entityA/disable'),0);
  });
}
