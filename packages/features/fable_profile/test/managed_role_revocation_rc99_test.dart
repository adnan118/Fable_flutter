import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_page.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';

const entityId='550e8400-e29b-41d4-a716-446655440001';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc99.role-revocation');
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'mock-bearer';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}

FableContract _contract()=>FableContract(
 contractHash:'rc99',projectName:'test-role-revocation',
 selectionMode:'advisory',featureIds:const {'managed-accounts'},
 operations:const {
  'entity.list':FableOperation('entity.list','GET','/managed-entities','rc99',
    enforceAuth:true),
  'entity.activate':FableOperation('entity.activate','POST',
    '/managed-entities/{id}/activate','rc99',enforceAuth:true),
  'entity.invites.mine':FableOperation('entity.invites.mine','GET',
    '/managed-entities/invitations/me','rc99',enforceAuth:true),
 });

Map<String,Object?> _entity(String role)=> {
 'id':entityId,'type':'hotel','nameAr':'فندق','nameEn':'Hotel',
 'status':'ACTIVE','visibility':'INVITE_ONLY',
 'collaborationEnabled':true,'managersCanInvite':true,
 'memberships':[{'access':role,'active':true}],
};

Dio _dio(Response<dynamic> Function(RequestOptions) reply){
 final client=Dio();
 client.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
   handler.resolve(reply(request));
 }));
 return client;
}
Response<dynamic> _ok(RequestOptions request,Object? result)=>
 Response(requestOptions:request,statusCode:200,data:result);

void main(){
 test('RC99 active role can be determined only from one confirmed membership',(){
  expect(FableManagedAccount.fromPayload(_entity('MANAGER')).effectiveAccess,'MANAGER');
  expect(FableManagedAccount.fromPayload(_entity('VIEWER')).effectiveAccess,'VIEWER');
  expect(FableManagedAccount.fromPayload(_entity('OWNER')).isOwner,true);
  expect(FableManagedAccount.fromPayload({
    ..._entity('MANAGER'),'memberships':[{'access':'MANAGER','active':false}],
  }).effectiveAccess,isNull);
 });

 test('RC99 malformed or conflicting membership is rejected',(){
  final invalid=[
    {'memberships':[{'access':'OWNER','active':true},{'access':'MANAGER','active':true}]},
    {'memberships':[{'access':'ADMIN','active':true}]},
    {'memberships':[{'access':'MANAGER','active':'yes'}]},
  ];
  for(final part in invalid){
    expect(()=>FableManagedAccount.fromPayload({..._entity('MANAGER'),...part}),
      throwsFormatException);
  }
 });

 testWidgets('RC99 role demotion clears selected entity and project context', (tester)async {
  var role='MANAGER',cleared=0,activated=0,rejectList=false;
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://test.invalid'),
    contract:_contract(),secureSession:_Session(),
    client:_dio((request){
      if(request.path=='/managed-entities' && request.method=='GET'){
        if(rejectList)return Response(requestOptions:request,statusCode:403,
          data:{'code':'PERMISSION_REVOKED'});
        return _ok(request,[_entity(role)]);
      }
      if(request.path=='/managed-entities/invitations/me')return _ok(request,[]);
      if(request.path=='/managed-entities/$entityId/activate')return _ok(request,{
        'managedEntityId':entityId,'access':'MANAGER',
        'header':{'name':'X-Fable-Managed-Entity-Id','value':entityId},
      });
      return _ok(request,{});
    }));
  addTearDown(gateway.dispose);
  await tester.pumpWidget(MaterialApp(home:FableManagedAccountsPage(
    gateway:gateway,contract:_contract(),
    onActivated:(_)=>activated++,
    onCleared:()=>cleared++,
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  expect(activated,1);
  expect(find.textContaining('Selected: '),findsOneWidget);
  final before=cleared;
  role='VIEWER';
  await tester.tap(find.byIcon(Icons.refresh));
  await tester.pumpAndSettle();
  expect(cleared,before+1);
  expect(find.textContaining('Selected: '),findsNothing);
  expect(find.text('MANAGER'),findsNothing);

  // A separate selection can be invalidated after an authorization failure.
  role='MANAGER';
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Selected: '),findsOneWidget);
  rejectList=true;
  final previous=cleared;
  await tester.tap(find.byIcon(Icons.refresh));
  await tester.pumpAndSettle();
  expect(cleared,previous+1);
  expect(find.textContaining('Selected: '),findsNothing);
 });
}
