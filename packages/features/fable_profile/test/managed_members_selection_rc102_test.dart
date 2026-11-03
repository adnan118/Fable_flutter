import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';
import 'package:fable_profile/src/managed_members_page.dart';

const entityA='550e8400-e29b-41d4-a716-446655440001';
const entityB='550e8400-e29b-41d4-a716-446655440002';
const viewerId='550e8400-e29b-41d4-a716-446655440003';
const inviteId='550e8400-e29b-41d4-a716-446655440004';
const url='https://api.example.test';

class _Session extends FableSecureSession {
  _Session():super(namespace:'rc102.members.test');
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'test-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId() async=>'0123456789abcdef0123456789abcdef';
}
FableContract _catalog()=>FableContract(
  contractHash:'rc102-contract',projectName:'rc102-project',
  selectionMode:'advisory',featureIds:const {'managed-accounts'},
  operations:const {
    'entity.list':FableOperation('entity.list','GET','/managed-entities',
      'rc102-contract',enforceAuth:true),
    'entity.members':FableOperation('entity.members','GET',
      '/managed-entities/{id}/members','rc102-contract',enforceAuth:true),
    'entity.sent.invites':FableOperation('entity.sent.invites','GET',
      '/managed-entities/{id}/invitations','rc102-contract',enforceAuth:true),
    'entity.remove.member':FableOperation('entity.remove.member','DELETE',
      '/managed-entities/{id}/members/{userId}','rc102-contract',enforceAuth:true),
    'entity.revoke.invite':FableOperation('entity.revoke.invite','DELETE',
      '/managed-entities/{id}/invitations/{invitationId}',
      'rc102-contract',enforceAuth:true),
  },
);
FableManagedAccount _entity()=>FableManagedAccount.fromPayload({
  'id':entityA,'type':'page','nameAr':'كيان أ','nameEn':'Entity A',
  'status':'ACTIVE','visibility':'INVITE_ONLY',
  'collaborationEnabled':true,'managersCanInvite':true,
  'memberships':[{'access':'OWNER','active':true}],
});
FableManagedAccountSelection _selection(String id)=>FableManagedAccountSelection(
  id:id,access:'OWNER',nameAr:'كيان',nameEn:'Entity',identityRevision:0,
);
Response<dynamic> _ok(RequestOptions request,Object? value)=>Response<dynamic>(
  requestOptions:request,statusCode:200,data:value,
);
const membersData={
  'items':[
    {'userId':viewerId,'access':'VIEWER','isOwner':false,'username':'secret-a'},
  ],
  'nextCursor':null,
};
const invitationsData={
  'items':[{'id':inviteId,'access':'VIEWER',
    'expiresAt':'2026-12-31T00:00:00Z','username':'invitee-a'}],
  'nextCursor':null,
};

class _Fixture {
  _Fixture({this.holdMembers=false}){
    client.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
      requests.add(request);
      if(request.path=='/managed-entities/$entityA/members'&&holdMembers){
        pendingMembers=Completer<Response<dynamic>>();
        handler.resolve(await pendingMembers!.future);
        return;
      }
      Object? result;
      if(request.path=='/managed-entities'&&request.method=='GET') {
        result=[{
          'id':entityA,'type':'page','nameAr':'كيان أ','nameEn':'Entity A',
          'status':'ACTIVE','visibility':'INVITE_ONLY',
          'collaborationEnabled':true,'managersCanInvite':true,
          'memberships':[{'access':currentAccess,'active':true}],
        }];
      } else if(request.path=='/managed-entities/$entityA/members') {
        result=membersData;
      } else if(request.path=='/managed-entities/$entityA/invitations') {
        result=invitationsData;
      } else if(request.method=='DELETE') {
        result=request.path.endsWith('/members/$viewerId')?{'removed':true}:null;
      }
      handler.resolve(_ok(request,result));
    }));
    gateway=FableAuthGateway(baseUri:Uri.parse(url),contract:_catalog(),
      secureSession:session,client:client);
    store=FableManagedEntityStore(session:session);
    store.bindBackend(gateway.managedEntityBackendIdentity);
    chosen=_selection(entityA);
    store.activate(chosen);
    repository=FableManagedAccountsRepository(gateway,_catalog());
  }
  final session=_Session();
  final client=Dio();
  final requests=<RequestOptions>[];
  final bool holdMembers;
  String currentAccess='OWNER';
  Completer<Response<dynamic>>? pendingMembers;
  late final FableAuthGateway gateway;
  late final FableManagedAccountsRepository repository;
  late final FableManagedEntityStore store;
  late final FableManagedAccountSelection chosen;

  Widget page({FableManagedEntityStore? overrideStore})=>MaterialApp(
    home:FableManagedMembersPage(repo:repository,entity:_entity(),
      selection:chosen,managedStore:overrideStore??store),
  );
  void dispose(){store.dispose();gateway.dispose();}
}

void main(){
  testWidgets('RC102 discards late A data after A→B→A with identical old selection',
  (tester)async{
    final f=_Fixture(holdMembers:true);
    addTearDown(f.dispose);
    await tester.pumpWidget(f.page());
    await tester.pump();
    await tester.pump(const Duration(milliseconds:50));
    expect(f.pendingMembers,isNotNull);
    f.store.activate(_selection(entityB));
    f.store.activate(f.chosen);
    await tester.pump();
    expect(find.byTooltip('Remove member'),findsNothing);
    expect(find.textContaining('Managed entity context changed'),findsOneWidget);
    f.pendingMembers!.complete(_ok(f.requests.firstWhere((r)=>
      r.path=='/managed-entities/$entityA/members'),membersData));
    await tester.pump();
    await tester.pump(const Duration(milliseconds:50));
    expect(find.text('secret-a'),findsNothing);
    expect(f.requests.where((r)=>r.method=='DELETE'),isEmpty);
  });

  testWidgets('RC102 refuses remove confirmation after context switch',
  (tester)async{
    final f=_Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    expect(find.text('secret-a'),findsOneWidget);
    await tester.tap(find.byTooltip('Remove member'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this member?'),findsOneWidget);
    f.store.activate(_selection(entityB));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(f.requests.where((r)=>r.method=='DELETE'),isEmpty);
    expect(find.byTooltip('Remove member'),findsNothing);
  });

  testWidgets('RC102 refuses invitation revoke confirmation after context switch',
  (tester)async{
    final f=_Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Revoke invitation'));
    await tester.tap(find.byTooltip('Revoke invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke this invitation?'),findsOneWidget);
    f.store.activate(_selection(entityB));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(f.requests.where((r)=>r.method=='DELETE'),isEmpty);
  });

  testWidgets('RC102 resume fails closed after Backend changes OWNER to VIEWER',
  (tester)async{
    final f=_Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    expect(find.text('secret-a'),findsOneWidget);
    f.currentAccess='VIEWER';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(f.store.selected,isNull);
    expect(find.text('secret-a'),findsNothing);
    expect(find.byTooltip('Remove member'),findsNothing);
    expect(f.requests.where((r)=>r.path=='/managed-entities'),isNotEmpty);
  });

  testWidgets('RC102 without Backend-bound selection store never loads member data',
  (tester)async{
    final f=_Fixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(MaterialApp(home:FableManagedMembersPage(
      repo:f.repository,entity:_entity(),selection:f.chosen,
    )));
    await tester.pumpAndSettle();
    expect(f.requests,isEmpty);
    expect(find.textContaining('Managed entity context changed'),findsOneWidget);
  });
}
