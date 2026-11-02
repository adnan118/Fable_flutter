import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Session extends FableSecureSession {
  @override int identityRevision = 0;
  @override Future<String?> get accessToken async => 'mock-access';
  @override Future<String?> get refreshToken async => null;
  @override Future<String> installationId() async => 'abcdef0123456789abcdef0123456789';
}

FableContract _contract({bool wrongPath = false}) => FableContract(
  contractHash:'rc94', projectName:'test',
  selectionMode:'advisory', featureIds:const {'auth'},
  operations:{
    'auth.username.availability':FableOperation('auth.username.availability',
      'GET',wrongPath?'/other/username/:username':
      '/auth/me/username/availability/:username','rc94',
      enforceAuth:true),
    'auth.username.update':const FableOperation('auth.username.update',
      'PATCH','/auth/me/username','rc94',enforceAuth:true),
    'auth.social.unlink':const FableOperation('auth.social.unlink',
      'DELETE','/auth/social/:provider','rc94',enforceAuth:true),
  },
);

Dio _mock(List<RequestOptions> calls,
    Object Function(RequestOptions) response) {
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler){
    calls.add(req);
    handler.resolve(Response(requestOptions:req,statusCode:200,data:response(req)));
  }));
  return dio;
}

void main() {
  test('RC94 availability uses contract route and backend answer',() async {
    final calls=<RequestOptions>[];
    final gateway=FableAuthGateway(
      baseUri:Uri.parse('https://fable.test'),contract:_contract(),
      secureSession:_Session(),
      client:_mock(calls, (_) => {'username':'member.one','available':false}));
    addTearDown(gateway.dispose);
    expect(gateway.canCheckUsernameAvailability,true);
    final result=await gateway.checkUsernameAvailability('member.one');
    expect(result.available,false);
    expect(calls.single.path,'/auth/me/username/availability/member.one');
  });

  test('RC94 rejects invalid and reserved names without network request',() async {
    final calls=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:_Session(),
      client:_mock(calls, (_)=>{}));
    addTearDown(gateway.dispose);
    for (final name in ['admin','name/other','AName','ab','a__?','نورس']) {
      await expectLater(gateway.checkUsernameAvailability(name),throwsArgumentError);
    }
    expect(calls,isEmpty);
  });

  test('RC94 update requires backend confirmation and preserves proof scope',() async {
    final calls=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:_Session(),
      client:_mock(calls, (_) => {'username':'member.new','changed':true}));
    addTearDown(gateway.dispose);
    final value=await gateway.updateUsername('member.new',
      securityChallengeId:'550e8400-e29b-41d4-a716-446655440013');
    expect(value.changed,true);
    expect(calls.single.method,'PATCH');
    expect((calls.single.data as Map)['securityChallengeId'],
      '550e8400-e29b-41d4-a716-446655440013');
  });

  test('RC94 unlink requires source-verified step-up and server ACK',()async {
    final calls=<RequestOptions>[];
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:_Session(),
      client:_mock(calls, (_)=>{'provider':'apple','unlinked':true,
        'externalCleanup':'transactional-outbox'}));
    addTearDown(gateway.dispose);
    await expectLater(gateway.unlinkSocialIdentity('github',
      securityChallengeId:'550e8400-e29b-41d4-a716-446655440013'),
      throwsArgumentError);
    final result=await gateway.unlinkSocialIdentity('apple',
      securityChallengeId:'550e8400-e29b-41d4-a716-446655440013');
    expect(result.unlinked,true);
    expect(result.externalCleanup,'transactional-outbox');
    expect(calls.single.path,'/auth/social/apple');
    expect(calls.single.headers['X-Security-Challenge-Id'],
      '550e8400-e29b-41d4-a716-446655440013');
  });

  test('RC94 rejects foreign/mismatched contract',()async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(wrongPath:true),secureSession:_Session());
    addTearDown(gateway.dispose);
    expect(gateway.canCheckUsernameAvailability,false);
    await expectLater(gateway.checkUsernameAvailability('member.good'),throwsStateError);
  });
}
