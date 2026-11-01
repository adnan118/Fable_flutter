import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_page.dart';

const entityId='550e8400-e29b-41d4-a716-446655440001';
const invitationId='550e8400-e29b-41d4-a716-446655440002';

class _Session extends FableSecureSession {
 @override int identityRevision=0;
 @override Future<String?> get accessToken async=>'token';
 @override Future<String?> get refreshToken async=>null;
 @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}
FableContract _contract()=>FableContract(
 contractHash:'contract',projectName:'test-managed-entities',
 selectionMode:'advisory',featureIds:const <String>{},
 operations:const {
  'entity.list':FableOperation('entity.list','GET',
    '/managed-entities','contract',enforceAuth:true),
  'entity.create':FableOperation('entity.create','POST',
    '/managed-entities','contract',enforceAuth:true),
  'entity.invites.mine':FableOperation('entity.invites.mine','GET',
    '/managed-entities/invitations/me','contract',enforceAuth:true),
  'entity.activate':FableOperation('entity.activate','POST',
    '/managed-entities/{id}/activate','contract',enforceAuth:true),
  'entity.invite':FableOperation('entity.invite','POST',
    '/managed-entities/{id}/invitations','contract',enforceAuth:true),
 },
);
Dio _dio(Future<Response<dynamic>> Function(RequestOptions) intercept){
 final client=Dio();
 client.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
  handler.resolve(await intercept(request));
 }));
 return client;
}
Response<dynamic> _ok(RequestOptions request,Object? data)=>
 Response(requestOptions:request,data:data,statusCode:200);
Map<String,Object?> _ownedEntity()=>{
 'id':entityId,'type':'hotel','nameAr':'فندق','nameEn':'Hotel',
 'slug':'example-hotel','status':'ACTIVE','visibility':'INVITE_ONLY',
 'collaborationEnabled':true,'managersCanInvite':true,
 'memberships':[{'access':'OWNER','active':true}],
};

void main(){
 testWidgets('create form exposes and transmits all Backend entity options',
 (tester)async{
  final requests=<RequestOptions>[];
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
    contract:_contract(),secureSession:_Session(),client:_dio((request)async{
      requests.add(request);
      if(request.method=='GET')return _ok(request,[]);
      if(request.method=='POST'&&request.path=='/managed-entities'){
        final payload=Map<String,dynamic>.from(request.data as Map);
        return _ok(request,{'data':{
          'id':entityId,'status':'ACTIVE',...payload,
        }});
      }
      return _ok(request,{});
    }));
  addTearDown(gateway.dispose);
  await tester.pumpWidget(MaterialApp(home:
    FableManagedAccountsPage(gateway:gateway,contract:_contract())));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create entity'));
  await tester.pumpAndSettle();
  expect(find.text('Public slug (optional)'),findsOneWidget);
  expect(find.text('Enable collaboration'),findsOneWidget);
  expect(find.text('Allow managers to invite'),findsOneWidget);
  await tester.enterText(find.widgetWithText(TextField,'Backend-enabled type'),'hotel');
  await tester.enterText(find.widgetWithText(TextField,'Arabic name'),'فندق');
  await tester.enterText(find.widgetWithText(TextField,'English name'),'Hotel');
  await tester.enterText(find.widgetWithText(TextField,'Public slug (optional)'),'new-hotel');
  await tester.tap(find.text('Private (no invitations)').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Invite only').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Enable collaboration'));
  await tester.tap(find.text('Enable collaboration'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Allow managers to invite'));
  await tester.tap(find.text('Allow managers to invite'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Create entity').last);
  await tester.tap(find.text('Create entity').last);
  await tester.pumpAndSettle();
  final post=requests.where((r)=>r.method=='POST'&&r.path=='/managed-entities').single;
  expect(post.data,{
    'type':'hotel','nameAr':'فندق','nameEn':'Hotel','slug':'new-hotel',
    'visibility':'INVITE_ONLY','collaborationEnabled':true,
    'managersCanInvite':true,
  });
 });

 testWidgets('invitation dialog offers MANAGER and requires extra confirmation',
 (tester)async{
  final requests=<RequestOptions>[];
  final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
    contract:_contract(),secureSession:_Session(),client:_dio((request)async{
      requests.add(request);
      if(request.path=='/managed-entities'&&request.method=='GET')
        return _ok(request,[_ownedEntity()]);
      if(request.path=='/managed-entities/invitations/me')
        return _ok(request,[]);
      if(request.path=='/managed-entities/$entityId/activate')
        return _ok(request,{'managedEntityId':entityId,'access':'OWNER',
          'header':{'name':'X-Fable-Managed-Entity-Id','value':entityId}});
      if(request.path=='/managed-entities/$entityId/invitations'){
        final input=Map<String,dynamic>.from(request.data as Map);
        return _ok(request,{'data':{'id':invitationId,
          'managedEntityId':entityId,
          'username':input['username'],'access':input['access'],
          'expiresAt':'2026-12-01T00:00:00.000Z'}});
      }
      return _ok(request,{});
    }));
  addTearDown(gateway.dispose);
  await tester.pumpWidget(MaterialApp(home:
    FableManagedAccountsPage(gateway:gateway,contract:_contract())));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Invite member'));
  await tester.pumpAndSettle();
  expect(find.text('Viewer (VIEWER)'),findsOneWidget);
  await tester.enterText(find.widgetWithText(TextField,'Existing username'),'alice');
  await tester.tap(find.text('Viewer (VIEWER)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Manager (MANAGER)').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send invitation'));
  await tester.pumpAndSettle();
  expect(find.textContaining('manager role'),findsOneWidget);
  expect(requests.where((r)=>r.path.endsWith('/invitations')&&r.method=='POST'),isEmpty);
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
  final post=requests.where((r)=>
    r.path=='/managed-entities/$entityId/invitations'&&r.method=='POST').single;
  expect(post.data,{'username':'alice','access':'MANAGER'});
 });
}
