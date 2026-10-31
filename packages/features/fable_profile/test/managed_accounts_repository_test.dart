import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';

const entityId='550e8400-e29b-41d4-a716-446655440001';
const inviteId='550e8400-e29b-41d4-a716-446655440002';
class _Session extends FableSecureSession {
  String? token='token';
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>token;
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
  @override Future<bool> clearSessionIfIdentity(int revision,
      {String? expectedAccessToken,String? expectedRefreshToken}) async {
    if(revision!=identityRevision)return false;
    token=null;identityRevision++;return true;
  }
}
FableContract catalog({bool installed=true})=>FableContract(
  contractHash:'hash',projectName:'fable-test',selectionMode:'advisory',
  featureIds:const <String>{},operations:installed?{
    'entity.list':const FableOperation('entity.list','GET','/managed-entities','hash',enforceAuth:true),
    'entity.activate':const FableOperation('entity.activate','POST',
      '/managed-entities/{id}/activate','hash',enforceAuth:true),
    'entity.create':const FableOperation('entity.create','POST','/managed-entities','hash',enforceAuth:true),
    'entity.details':const FableOperation('entity.details','GET',
      '/managed-entities/{id}','hash',enforceAuth:true),
    'entity.update':const FableOperation('entity.update','PATCH',
      '/managed-entities/{id}','hash',enforceAuth:true),
    'entity.invites':const FableOperation('entity.invites','GET',
      '/managed-entities/invitations/me','hash',enforceAuth:true),
    'entity.accept':const FableOperation('entity.accept','POST',
      '/managed-entities/invitations/{invitationId}/accept','hash',enforceAuth:true),
    'entity.decline':const FableOperation('entity.decline','POST',
      '/managed-entities/invitations/{invitationId}/decline','hash',enforceAuth:true),
    'entity.invite':const FableOperation('entity.invite','POST',
      '/managed-entities/{id}/invitations','hash',enforceAuth:true),
    'auth.2fa.status':const FableOperation('auth.2fa.status','GET','/auth/2fa/status','hash',enforceAuth:true),
    'auth.otp.request':const FableOperation('auth.otp.request','POST','/auth/otp/request','hash',enforceAuth:true),
    'auth.otp.verify':const FableOperation('auth.otp.verify','POST','/auth/otp/verify','hash',enforceAuth:true),
    'entity.disable':const FableOperation('entity.disable','POST','/managed-entities/{id}/disable','hash',enforceAuth:true),
    'entity.enable':const FableOperation('entity.enable','POST','/managed-entities/{id}/enable','hash',enforceAuth:true),
    'entity.delete.request':const FableOperation('entity.delete.request','POST','/managed-entities/{id}/delete-request','hash',enforceAuth:true),
    'entity.restore':const FableOperation('entity.restore','POST','/managed-entities/{id}/restore','hash',enforceAuth:true),
    'entity.members':const FableOperation('entity.members','GET',
      '/managed-entities/{id}/members','hash',enforceAuth:true),
    'entity.member.remove':const FableOperation('entity.member.remove','DELETE',
      '/managed-entities/{id}/members/{userId}','hash',enforceAuth:true),
    'entity.sent.invites':const FableOperation('entity.sent.invites','GET',
      '/managed-entities/{id}/invitations','hash',enforceAuth:true),
    'entity.invite.revoke':const FableOperation('entity.invite.revoke','DELETE',
      '/managed-entities/{id}/invitations/{invitationId}','hash',enforceAuth:true),
    'business.op':const FableOperation('business.op','GET','/business/me','hash',enforceAuth:true),
  }:const <String,FableOperation>{});
Map<String,Object?> entity()=>{
  'id':entityId,'type':'page','nameAr':'نادي الشاطئ','nameEn':'Beach Club',
  'status':'ACTIVE','visibility':'INVITE_ONLY','collaborationEnabled':true,
  'managersCanInvite':false,
};
Dio dio(Future<Response<dynamic>> Function(RequestOptions) callback){
  final d=Dio();d.interceptors.add(InterceptorsWrapper(onRequest:(o,h)async{
    h.resolve(await callback(o));
  }));return d;
}
Response<dynamic> ok(RequestOptions r,Object? data)=>Response<dynamic>(
  requestOptions:r,statusCode:200,data:data);

void main(){
  test('Managed entity list, activation and scoped requests use only declared Backend ops',()async{
    final session=_Session(),seen=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        seen.add(req);
        if(req.path=='/managed-entities')return ok(req,[{
          ...entity(),'memberships':[{'access':'OWNER','active':true}]}]);
        if(req.path=='/managed-entities/'+entityId+'/activate')return ok(req,{
          'managedEntityId':entityId,'access':'OWNER',
          'header':{'name':'X-Fable-Managed-Entity-Id','value':entityId},
        });
        if(req.path=='/business/me')return ok(req,{'businessId':entityId});
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    expect(repo.canList,true);
    final items=await repo.listMine();
    expect(items.length,1);
    final chosen=await repo.activate(items.single);
    expect(chosen.access,'OWNER');
    expect(chosen.id,entityId);
    expect(await repo.executeInContext(chosen,'business.op'),{'businessId':entityId});
    expect(seen.last.headers['X-Fable-Managed-Entity-Id'],entityId);
    expect(seen.first.headers.containsKey('X-Fable-Managed-Entity-Id'),false);
    session.identityRevision++;
    await expectLater(repo.executeInContext(chosen,'business.op'),throwsStateError);
  });

  test('Managed context activation cannot invent privilege if backend response disagrees',()async{
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async=>
        ok(req,{'managedEntityId':entityId,'access':'OWNER',
          'header':{'name':'X-Fable-Managed-Entity-Id','value':inviteId}})));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    await expectLater(repo.activate(FableManagedAccount.fromPayload(entity())),
      throwsFormatException);
  });

  test('Missing Managed Accounts capability never synthesizes endpoints',()async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(installed:false),secureSession:_Session());
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog(installed:false));
    expect(repo.canList,false);
    expect(repo.canActivate,false);
    expect(repo.canCreate,false);
    await expectLater(repo.listMine(),throwsStateError);
  });
  test('Membership status and invitation roles are validated, not inferred',(){
    expect(FableManagedAccount.fromPayload(entity()).status,'ACTIVE');
    expect(()=>FableManagedAccount.fromPayload({...entity(),'status':'ADMIN'}),
      throwsFormatException);
    expect(()=>FableManagedAccount.fromPayload({...entity(),'id':'fake'}),
      throwsFormatException);
    final invitation=FableManagedInvitation.fromPayload({
      'id':inviteId,'access':'VIEWER','expiresAt':'2026-11-30T00:00:00Z',
      'managedAccount':{'id':entityId,'nameAr':'نادي الشاطئ'},
    });
    expect(invitation.access,'VIEWER');
    expect(()=>FableManagedInvitation.fromPayload({
      'id':inviteId,'access':'OWNER','expiresAt':'2026-11-30T00:00:00Z',
      'managedAccount':{'id':entityId,'nameAr':'نادي الشاطئ'},
    }),throwsFormatException);
  });

  test('Owner lifecycle chooses authoritative TWO_FACTOR proof and consumes it only on backend action',()async{
    final session=_Session(),calls=<RequestOptions>[],challenge='550e8400-e29b-41d4-a716-446655440003';
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        calls.add(req);
        if(req.path=='/auth/2fa/status')return ok(req,{'enabled':true});
        if(req.path=='/auth/otp/request'){
          expect(req.data,{'purpose':'TWO_FACTOR'});
          return ok(req,{'challengeId':challenge});
        }
        if(req.path=='/auth/otp/verify'){
          expect(req.data,{'challengeId':challenge,'code':'123456'});
          return ok(req,{'verified':true,'challengeId':challenge,'purpose':'TWO_FACTOR'});
        }
        if(req.path=='/managed-entities/'+entityId+'/disable'){
          expect(req.data,{'otpChallengeId':challenge});
          return ok(req,{'data':{'code':'MANAGED_ENTITY_DISABLED'}});
        }
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    final owner=FableManagedAccount.fromPayload({
      ...entity(),'memberships':[{'access':'OWNER','active':true}],
    });
    expect(owner.isOwner,true);
    expect(repo.canLifecycle('disable'),true);
    final pending=await repo.requestLifecycleChallenge(owner,'disable');
    expect(pending.purpose,'TWO_FACTOR');
    await repo.verifyAndApplyLifecycle(pending,'123456');
    expect(calls.map((r)=>r.path).toList(),[
      '/auth/2fa/status','/auth/otp/request','/auth/otp/verify',
      '/managed-entities/'+entityId+'/disable',
    ]);
    expect(calls.last.headers.containsKey('X-Fable-Managed-Entity-Id'),false);
    expect(calls.last.headers.containsKey('X-Security-Challenge-Id'),false);
  });
  test('SENSITIVE_ACTION lifecycle requires Backend 2FA=disabled, denies members and stale identity',()async{
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        if(req.path=='/auth/2fa/status')return ok(req,{'enabled':false});
        if(req.path=='/auth/otp/request')return ok(req,{'challengeId':inviteId});
        if(req.path=='/auth/otp/verify')return ok(req,{
          'verified':true,'challengeId':inviteId,'purpose':'SENSITIVE_ACTION'});
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    final member=FableManagedAccount.fromPayload(entity());
    expect(member.isOwner,false);
    await expectLater(repo.requestLifecycleChallenge(member,'disable'),throwsStateError);
    final owner=FableManagedAccount.fromPayload({
      ...entity(),'memberships':[{'access':'OWNER','active':true}]});
    final pending=await repo.requestLifecycleChallenge(owner,'disable');
    expect(pending.purpose,'SENSITIVE_ACTION');
    session.identityRevision++;
    await expectLater(repo.verifyAndApplyLifecycle(pending,'123456'),throwsStateError);
  });
  test('Entity lifecycle rejects wrong status, missing contract, and unverified owner claims',()async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(installed:false),secureSession:_Session());
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog(installed:false));
    expect(repo.canLifecycle('disable'),false);
    final disabled=FableManagedAccount.fromPayload({
      ...entity(),'status':'DISABLED',
      'memberships':[{'access':'OWNER','active':true}]});
    await expectLater(repo.requestLifecycleChallenge(disabled,'disable'),throwsStateError);
    final forged=FableManagedAccount.fromPayload({
      ...entity(),'memberships':[{'access':'MANAGER','active':true}]});
    expect(forged.isOwner,false);
  });


  test('Owner can page real members, remove nonowner and revoke sent invitations',()async{
    final seen=<RequestOptions>[];
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        seen.add(req);
        if(req.path=='/managed-entities/'+entityId+'/activate')return ok(req,{
          'managedEntityId':entityId,'access':'OWNER',
          'header':{'name':'X-Fable-Managed-Entity-Id','value':entityId}});
        if(req.path=='/managed-entities/'+entityId+'/members')return ok(req,{
          'items':[{'userId':entityId,'access':'OWNER','isOwner':true,
              'username':'owner','joinedAt':'2026-09-01T00:00:00Z'},
            {'userId':inviteId,'access':'VIEWER','isOwner':false,
              'username':'viewer','joinedAt':'2026-09-02T00:00:00Z'}],
          'nextCursor':null});
        if(req.path=='/managed-entities/'+entityId+'/members/'+inviteId)
          return ok(req,{'removed':true});
        if(req.path=='/managed-entities/'+entityId+'/invitations')
          return ok(req,{'items':[{
            'id':inviteId,'access':'VIEWER','username':'invitee',
            'expiresAt':'2026-11-30T00:00:00Z',
          }],'nextCursor':null});
        return ok(req,{'data':null,'code':'MANAGED_ENTITY_INVITATION_REVOKED'});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    final owner=FableManagedAccount.fromPayload({
      ...entity(),'memberships':[{'access':'OWNER','active':true}]});
    final selected=await repo.activate(owner);
    final page=await repo.members(owner,selected);
    expect(page.items.length,2);
    expect(page.items.first.isOwner,true);
    await expectLater(repo.removeMember(owner,selected,page.items.first),throwsStateError);
    expect(await repo.removeMember(owner,selected,page.items.last),true);
    final sent=await repo.sentInvitations(owner,selected);
    expect(sent.items.single.username,'invitee');
    await repo.revokeSentInvitation(owner,selected,sent.items.single);
    expect(seen.any((x)=>x.method=='DELETE'&&
      x.path=='/managed-entities/'+entityId+'/members/'+inviteId),true);
    expect(seen.any((x)=>x.method=='DELETE'&&
      x.path=='/managed-entities/'+entityId+'/invitations/'+inviteId),true);
    session.identityRevision++;
    await expectLater(repo.members(owner,selected),throwsStateError);
  });
  test('Membership and invitation pagination fails closed for forged access or cursor',()async{
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async=>
        ok(req,{'items':[],'nextCursor':'https://attacker.test'})));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    final entityOwner=FableManagedAccount.fromPayload({
      ...entity(),'memberships':[{'access':'OWNER','active':true}]});
    final selected=FableManagedAccountSelection(id:entityId,access:'OWNER',
      nameAr:'نادي الشاطئ',nameEn:'Beach Club',identityRevision:session.identityRevision);
    await expectLater(repo.members(entityOwner,selected),throwsFormatException);
    await expectLater(repo.members(entityOwner,selected,after:'bad'),throwsArgumentError);
    final fake=FableManagedAccount.fromPayload(entity());
    await expectLater(repo.members(fake,selected),throwsStateError);
    await expectLater(repo.sentInvitations(fake,selected),throwsStateError);
  });


  test('Managed detail read and owner patch use only exported routes and changed flags',()async{
    final session=_Session(),seen=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        seen.add(req);
        if(req.method=='GET'&&req.path=='/managed-entities/'+entityId)
          return ok(req,{...entity(),'slug':'beach-club',
            'memberships':[{'access':'OWNER','active':true}]});
        if(req.method=='PATCH'&&req.path=='/managed-entities/'+entityId)
          return ok(req,{'data':{
            ...entity(),'slug':'beach-club','nameEn':'Updated Club',
            'visibility':'PRIVATE','collaborationEnabled':false,
            'managersCanInvite':false,
          }});
        return ok(req,{});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    final owner=FableManagedAccount.fromPayload({...entity(),'slug':'beach-club',
      'memberships':[{'access':'OWNER','active':true}]});
    expect(repo.canReadDetails,true);
    expect(repo.canUpdateDetails,true);
    final details=await repo.readDetails(owner);
    expect(details.slug,'beach-club');
    await repo.updateDetails(owner,nameAr:'نادي الشاطئ',nameEn:'Updated Club',
      visibility:'PRIVATE',collaborationEnabled:true,managersCanInvite:true,
      slug:'beach-club');
    final patch=seen.last;
    expect(patch.method,'PATCH');
    expect(patch.path,'/managed-entities/'+entityId);
    expect(patch.data,{
      'nameEn':'Updated Club','visibility':'PRIVATE','collaborationEnabled':false,
    });
    expect(seen.every((r)=>r.headers.containsKey('X-Fable-Managed-Entity-Id')==false),true);
  });

  test('Editing fails closed on missing operations, nonowner, invalid slug and stale identity',()async{
    final missingGateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(installed:false),secureSession:_Session());
    addTearDown(missingGateway.dispose);
    final missing=FableManagedAccountsRepository(missingGateway,catalog(installed:false));
    expect(missing.canUpdateDetails,false);
    expect(missing.canReadDetails,false);
    final owner=FableManagedAccount.fromPayload({...entity(),
      'memberships':[{'access':'OWNER','active':true}]});
    await expectLater(missing.updateDetails(owner,nameAr:'One',nameEn:'Two',
      visibility:'PUBLIC',collaborationEnabled:true,managersCanInvite:false),
      throwsStateError);
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://api.example.test'),
      contract:catalog(),secureSession:session,client:dio((req)async{
        session.identityRevision++;
        return ok(req,{...entity(),
          'memberships':[{'access':'OWNER','active':true}]});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,catalog());
    await expectLater(repo.updateDetails(FableManagedAccount.fromPayload(entity()),
      nameAr:'A',nameEn:'B',visibility:'PUBLIC',
      collaborationEnabled:true,managersCanInvite:false),throwsStateError);
    await expectLater(repo.updateDetails(owner,nameAr:'A',nameEn:'B',
      visibility:'PUBLIC',collaborationEnabled:true,managersCanInvite:false,
      slug:'bad slug'),throwsArgumentError);
    await expectLater(repo.readDetails(owner),throwsA(isA<FableApiException>()));
    expect(()=>FableManagedAccount.fromPayload({...entity(),'slug':'invalid slug'}),
      throwsFormatException);
  });
}
