import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/managed_accounts_repository.dart';

const inviteId='550e8400-e29b-41d4-a716-446655440002';
const entityId='550e8400-e29b-41d4-a716-446655440001';

class _Session extends FableSecureSession {
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'simulated-session';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'0123456789abcdef0123456789abcdef';
}

FableContract _catalog()=>FableContract(
  contractHash:'rc96',projectName:'rc96',selectionMode:'advisory',
  featureIds:const {'profile'},operations:{
    'invitation.accept':const FableOperation('invitation.accept','POST',
      '/managed-entities/invitations/{invitationId}/accept','rc96',
      enforceAuth:true),
    'invitation.decline':const FableOperation('invitation.decline','POST',
      '/managed-entities/invitations/{invitationId}/decline','rc96',
      enforceAuth:true),
  });
Dio _dio(Future<Response<dynamic>> Function(RequestOptions) response){
  final d=Dio();
  d.interceptors.add(InterceptorsWrapper(onRequest:(req,handler)async{
    handler.resolve(await response(req));
  }));
  return d;
}
Response<dynamic> _ok(RequestOptions req,Object? body)=>Response<dynamic>(
  requestOptions:req,statusCode:200,data:body);

void main(){
  test('RC96 accept requires confirmed membership, decline exact code',()async{
    final seen=<RequestOptions>[],session=_Session();
    final contract=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:contract,secureSession:session,client:_dio((req)async{
        seen.add(req);
        if(req.path.endsWith('/accept')){
          return _ok(req,{'success':true,
            'messageCode':'MANAGED_ENTITY_INVITATION_ACCEPTED',
            'data':{'managedEntityId':entityId,'access':'VIEWER'}});
        }
        return _ok(req,{'success':true,
          'messageCode':'MANAGED_ENTITY_INVITATION_DECLINED','data':null});
      }));
    addTearDown(gateway.dispose);
    final repo=FableManagedAccountsRepository(gateway,contract);
    await repo.respondToInvitation(inviteId,accept:true);
    await repo.respondToInvitation(inviteId,accept:false);
    expect(seen.map((x)=>x.path).toList(),[
      '/managed-entities/invitations/$inviteId/accept',
      '/managed-entities/invitations/$inviteId/decline',
    ]);
    expect(seen.every((r)=>r.headers.containsKey('Authorization')),true);
  });

  test('RC96 wrong access and forged success are rejected',()async{
    final contract=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:contract,secureSession:_Session(),client:_dio((req)async=>
        _ok(req,{'success':true,
          'messageCode':'MANAGED_ENTITY_INVITATION_ACCEPTED',
          'data':{'managedEntityId':entityId,'access':'OWNER'}})));
    addTearDown(gateway.dispose);
    await expectLater(FableManagedAccountsRepository(gateway,contract)
      .respondToInvitation(inviteId,accept:true),throwsFormatException);
  });

  test('RC96 previous-user invitation success discarded after identity switch',()async{
    final session=_Session(),contract=_catalog();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:contract,secureSession:session,client:_dio((req)async{
        session.identityRevision++;
        return _ok(req,{'success':true,
          'messageCode':'MANAGED_ENTITY_INVITATION_DECLINED','data':null});
      }));
    addTearDown(gateway.dispose);
    await expectLater(FableManagedAccountsRepository(gateway,contract)
      .respondToInvitation(inviteId,accept:false),
      throwsA(isA<FableApiException>()));
  });
}
