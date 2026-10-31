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
    'entity.invites':const FableOperation('entity.invites','GET',
      '/managed-entities/invitations/me','hash',enforceAuth:true),
    'entity.accept':const FableOperation('entity.accept','POST',
      '/managed-entities/invitations/{invitationId}/accept','hash',enforceAuth:true),
    'entity.decline':const FableOperation('entity.decline','POST',
      '/managed-entities/invitations/{invitationId}/decline','hash',enforceAuth:true),
    'entity.invite':const FableOperation('entity.invite','POST',
      '/managed-entities/{id}/invitations','hash',enforceAuth:true),
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
        if(req.path=='/managed-entities')return ok(req,[entity()]);
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
}
