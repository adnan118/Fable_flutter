import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// جلسة ذاكرة لا تُشغّل Keychain/Keystore؛ اختبارات الأجهزة الحقيقية
/// وRefresh replay في MySQL ما زالت شروط قبول مستقلة.
class _Session extends FableSecureSession {
  String? access;
  String? refresh;
  @override int identityRevision = 0;
  @override Future<String?> get accessToken async => access;
  @override Future<String?> get refreshToken async => refresh;
  @override Future<String> installationId() async =>
      '0123456789abcdef0123456789abcdef';
  @override Future<bool> replaceTokensIfIdentity({
    required int expectedIdentity, required String accessToken,
    String? refreshToken,
  }) async {
    if(expectedIdentity!=identityRevision)return false;
    access=accessToken;refresh=refreshToken;identityRevision++;
    return true;
  }
  @override Future<bool> saveTokensIfIdentity({
    required int expectedIdentity,required String accessToken,
    String? refreshToken,String? expectedRefreshToken,
  }) async {
    if(expectedIdentity!=identityRevision||
        (expectedRefreshToken!=null&&expectedRefreshToken!=refresh))return false;
    access=accessToken;refresh=refreshToken;
    return true;
  }
  @override Future<bool> clearSessionIfIdentity(int expectedIdentity,{
    String? expectedAccessToken,String? expectedRefreshToken,
  })async{
    if(expectedIdentity!=identityRevision||
       (expectedAccessToken!=null&&access!=expectedAccessToken)||
       (expectedRefreshToken!=null&&refresh!=expectedRefreshToken))return false;
    access=null;refresh=null;identityRevision++;
    return true;
  }
}
FableContract _contract({bool login=false,bool refresh=false}) =>
    FableContract(contractHash:List<String>.filled(64,'a').join(),
      operations:{
        if(login)'auth.login':const FableOperation(
          'auth.login','POST','/auth/login','hash',
          requiresAuth:false,enforceAuth:true),
        if(refresh)'auth.refresh':const FableOperation(
          'auth.refresh','POST','/auth/refresh','hash',
          requiresAuth:false,enforceAuth:true),
        'auth.sessions':const FableOperation(
          'auth.sessions','GET','/auth/sessions','hash',
          requiresAuth:true,enforceAuth:true),
      },
      featureIds:const {'auth'},projectName:'rc84',
      selectionMode:'explicit');

Dio _stub(Future<Response<dynamic>> Function(RequestOptions) reply){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,h)async{
    try {h.resolve(await reply(req));}
    catch(error){h.reject(DioException(requestOptions:req,error:error));}
  }));
  return dio;
}
Response<dynamic> _response(RequestOptions req,int status,Object? data)=>
  Response(requestOptions:req,statusCode:status,data:data);
const futureExpiry='2099-01-01T00:00:00Z';

void main(){
  test('mandatory password change is returned by Fable before any ordinary account UI',()async{
    final session=_Session();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(login:true),secureSession:session,
      client:_stub((req)async=>_response(req,200,{
        'accessToken':'a','refreshToken':List<String>.filled(64,'r').join(),
        'expiresAt':futureExpiry,'mustChangePassword':true,
      })));
    addTearDown(gateway.dispose);
    final login=await gateway.login(identifier:'demo@example.test',password:'valid-test',platform:'android');
    expect(login.authenticated,true);
    expect(login.mustChangePassword,true);
    expect(session.access,'a');
  });

  test('missing or malformed password-change decision cannot save credentials',()async{
    for(final value in <Object?>[null,'true',1]){
      final session=_Session();
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
        contract:_contract(login:true),secureSession:session,
        client:_stub((req)async=>_response(req,200,{
          'accessToken':'a','refreshToken':List<String>.filled(64,'r').join(),
          'expiresAt':futureExpiry,
          if(value!=null)'mustChangePassword':value,
        })));
      await expectLater(gateway.login(
        identifier:'demo@example.test',password:'valid-test',platform:'ios'),
        throwsFormatException);
      expect(session.access,isNull);
      gateway.dispose();
    }
  });

  test('missing, expired, or non-UTC session expiry cannot save credentials',()async{
    for(final expiry in <Object?>[null,'2020-01-01T00:00:00Z','2099-01-01T00:00:00']){
      final session=_Session();
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
        contract:_contract(login:true),secureSession:session,
        client:_stub((req)async=>_response(req,200,{
          'accessToken':'a','refreshToken':List<String>.filled(64,'r').join(),
          'mustChangePassword':false,
          if(expiry!=null)'expiresAt':expiry,
        })));
      await expectLater(gateway.login(
        identifier:'demo@example.test',password:'valid-test',platform:'ios'),
        throwsFormatException);
      expect(session.access,isNull);
      gateway.dispose();
    }
  });

  test('refresh replay grace 409 never repeats the consumed refresh token or clears credentials',()async{
    final session=_Session()
      ..access='old-access'
      ..refresh=List<String>.filled(64,'r').join();
    var refreshCalls=0;
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(refresh:true),secureSession:session,
      client:_stub((req)async{
        if(req.path=='/auth/refresh'){
          refreshCalls++;
          expect(req.data['refreshToken'],List<String>.filled(64,'r').join());
          return _response(req,409,{'code':'AUTH_REFRESH_ALREADY_ROTATED'});
        }
        return _response(req,401,{'code':'AUTH_TOKEN_INVALID'});
      }));
    addTearDown(gateway.dispose);
    await expectLater(gateway.listActiveSessions(),
      throwsA(isA<FableApiException>().having((e)=>e.code,'code','AUTH_REFRESH_ALREADY_ROTATED')));
    expect(refreshCalls,1);
    expect(session.access,'old-access');
    expect(session.refresh,List<String>.filled(64,'r').join());
  });

  test('confirmed server refresh replay 401 clears only matching session',()async{
    final session=_Session()
      ..access='old-access'
      ..refresh=List<String>.filled(64,'r').join();
    var refreshCalls=0;
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(refresh:true),secureSession:session,
      client:_stub((req)async{
        if(req.path=='/auth/refresh'){
          refreshCalls++;
          return _response(req,401,{'code':'AUTH_REFRESH_REPLAY_DETECTED'});
        }
        return _response(req,401,{'code':'AUTH_TOKEN_INVALID'});
      }));
    addTearDown(gateway.dispose);
    await expectLater(gateway.listActiveSessions(),throwsA(isA<FableApiException>()));
    expect(refreshCalls,1);
    expect(session.access,isNull);
    expect(session.refresh,isNull);
  });

  test('temporary refresh outage preserves tokens and never starts a mutation retry',()async{
    final session=_Session()
      ..access='old-access'
      ..refresh=List<String>.filled(64,'r').join();
    var refreshCalls=0;
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(refresh:true),secureSession:session,
      client:_stub((req)async{
        if(req.path=='/auth/refresh'){
          refreshCalls++;
          return _response(req,503,{'code':'UPSTREAM_UNAVAILABLE'});
        }
        return _response(req,401,{'code':'AUTH_TOKEN_INVALID'});
      }));
    addTearDown(gateway.dispose);
    await expectLater(gateway.listActiveSessions(),throwsA(isA<FableApiException>()));
    expect(refreshCalls,1);
    expect(session.access,'old-access');
    expect(session.refresh,List<String>.filled(64,'r').join());
  });
}
