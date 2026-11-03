import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_page.dart';

const entityA='550e8400-e29b-41d4-a716-446655440001';
const entityB='550e8400-e29b-41d4-a716-446655440002';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc103.parent.context');
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'example-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}
FableContract _contract()=>FableContract(
  contractHash:'rc103-contract',projectName:'rc103-test',
  selectionMode:'advisory',featureIds:const {'managed-accounts'},
  operations:const {
    'managed.list':FableOperation('managed.list','GET',
      '/managed-entities','rc103-contract',enforceAuth:true),
    'managed.activate':FableOperation('managed.activate','POST',
      '/managed-entities/{id}/activate','rc103-contract',enforceAuth:true),
    'managed.invite':FableOperation('managed.invite','POST',
      '/managed-entities/{id}/invitations','rc103-contract',enforceAuth:true),
    'managed.invitations':FableOperation('managed.invitations','GET',
      '/managed-entities/invitations/me','rc103-contract',enforceAuth:true),
  },
);
Map<String,Object?> _entity()=> {
  'id':entityA,'type':'site','nameAr':'كيان أ','nameEn':'Entity A',
  'status':'ACTIVE','visibility':'INVITE_ONLY',
  'collaborationEnabled':true,'managersCanInvite':true,
  'memberships':[{'access':'OWNER','active':true}],
};

void main(){
  testWidgets('RC103 parent rejects invitation confirmation after A→B→A', (tester)async {
    final session=_Session(),contract=_contract(),requests=<RequestOptions>[];
    final client=Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest:(r,h) {
      requests.add(r);
      Object? payload;
      if(r.method=='GET'&&r.path=='/managed-entities')payload=[_entity()];
      if(r.method=='GET'&&r.path=='/managed-entities/invitations/me')payload=[];
      if(r.method=='POST'&&r.path=='/managed-entities/$entityA/activate'){
        payload={'managedEntityId':entityA,'access':'OWNER',
          'header':{'name':'X-Fable-Managed-Entity-Id','value':entityA}};
      }
      if(r.method=='POST'&&r.path=='/managed-entities/$entityA/invitations'){
        payload={'data':{'id':entityB,'managedEntityId':entityA,
          'username':'alice','access':'VIEWER',
          'expiresAt':'2026-12-01T00:00:00.000Z'}};
      }
      h.resolve(Response<dynamic>(requestOptions:r,statusCode:200,data:payload));
    }));
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:contract,secureSession:session,client:client);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home:FableManagedEntityScope(
      store:store,
      child:FableManagedAccountsPage(gateway:gateway,contract:contract),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    final chosen=store.selected;
    expect(chosen,isNotNull);
    expect(chosen?.id,entityA);
    expect(find.text('Invite member'),findsOneWidget);

    await tester.tap(find.text('Invite member'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'Existing username'),'alice');
    store.activate(const FableManagedEntitySelection(
      id:entityB,access:'VIEWER',nameAr:'كيان ب',nameEn:'Entity B',
      identityRevision:0,
    ));
    store.activate(chosen!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(requests.where((r)=>r.method=='POST'&&
      r.path.endsWith('/invitations')),isEmpty);
    expect(find.text('Invite member'),findsNothing);
  });

  testWidgets('RC103 parent drops stale selected management controls on store clear',
  (tester)async {
    final session=_Session(),contract=_contract(),requests=<RequestOptions>[];
    final client=Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest:(r,h) {
      requests.add(r);
      final payload=r.method=='GET'
        ? r.path=='/managed-entities'?[_entity()]:[]
        : {'managedEntityId':entityA,'access':'OWNER',
           'header':{'name':'X-Fable-Managed-Entity-Id','value':entityA}};
      h.resolve(Response<dynamic>(requestOptions:r,statusCode:200,data:payload));
    }));
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:contract,secureSession:session,client:client);
    addTearDown(gateway.dispose);
    final store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home:FableManagedEntityScope(
      store:store,child:FableManagedAccountsPage(gateway:gateway,contract:contract),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Invite member'),findsOneWidget);
    store.clear();
    await tester.pumpAndSettle();
    expect(find.text('Invite member'),findsNothing);
    expect(find.textContaining('Selected: '),findsNothing);
  });
}
