import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

/// اختبارات عقد Fable RC66 للعامل الثاني، لا تمثل E2E على جهاز أو OTP فعلي.
/// لا تحتوي أي بيانات إنتاجية ولا تُحفظ كلمة السر أو TwoFactorToken في التخزين.
class _Session extends FableSecureSession {
  String? access, refresh;
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>access;
  @override Future<String?> get refreshToken async=>refresh;
  @override Future<String> installationId() async=>
    '0123456789abcdef0123456789abcdef';
  @override Future<bool> replaceTokensIfIdentity({
    required int expectedIdentity,required String accessToken,
    String? refreshToken}) async {
    if(expectedIdentity!=identityRevision)return false;
    identityRevision++;
    access=accessToken;refresh=refreshToken;
    return true;
  }
}
const pendingToken='tttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt';
const otpChallenge='550e8400-e29b-41d4-a716-446655440000';
const futureExpiry='2099-01-01T00:00:00Z';

FableOperation _op(String id,String method,String path,{
    bool protected=false,bool enforced=true})=>
  FableOperation(id,method,path,'hash',requiresAuth:protected,enforceAuth:enforced);

FableContract _catalog({FableOperation? request,FableOperation? complete})=>
  FableContract(
    contractHash:List<String>.filled(64,'a').join(),
    projectName:'rc85',selectionMode:'explicit',
    featureIds:const {'auth'},
    operations:{
      'auth.login':_op('auth.login','POST','/auth/login'),
      'auth.2fa.login.request':request ?? _op('auth.2fa.login.request',
          'POST','/auth/2fa/login/request'),
      'auth.2fa.login.complete':complete ?? _op('auth.2fa.login.complete',
          'POST','/auth/2fa/login/complete'),
    });

Dio _mock(Future<Response<dynamic>> Function(RequestOptions) respond){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler)async{
    try {handler.resolve(await respond(req));}
    catch(e){handler.reject(DioException(requestOptions:req,error:e));}
  }));
  return dio;
}
Response<dynamic> _answer(RequestOptions req,Object? data)=>
  Response<dynamic>(requestOptions:req,statusCode:200,data:data);

void main(){
  test('Fable 2FA request and completion preserve exact device metadata, without saving before OTP',() async{
    final session=_Session();
    final calls=<String>[];
    final gateway=FableAuthGateway(
      baseUri:Uri.parse('https://fable.test'),contract:_catalog(),
      secureSession:session,client:_mock((req)async{
        calls.add(req.path);
        if(req.path=='/auth/login'){
          expect(req.data,{
            'identifier':'demo@example.test',
            'password':'test-password',
            'clientType':'flutter',
            'installationId':'0123456789abcdef0123456789abcdef',
            'platform':'ios','deviceName':'Work iPhone','appVersion':'2.3.1+45',
          });
          return _answer(req,{'requiresTwoFactor':true,'twoFactorToken':pendingToken,
            'methods':['EMAIL_OTP','PHONE_OTP'],'expiresAt':futureExpiry});
        }
        if(req.path=='/auth/2fa/login/request'){
          expect(req.method,'POST');
          expect(req.headers.containsKey('Authorization'),false);
          expect(req.data,{
            'twoFactorToken':pendingToken,
            'clientType':'flutter',
            'installationId':'0123456789abcdef0123456789abcdef',
            'preferredChannel':'EMAIL',
          });
          return _answer(req,{'challengeId':otpChallenge});
        }
        if(req.path=='/auth/2fa/login/complete'){
          expect(req.method,'POST');
          expect(req.data,{
            'twoFactorToken':pendingToken,'challengeId':otpChallenge,
            'code':'123456','clientType':'flutter',
            'installationId':'0123456789abcdef0123456789abcdef',
            'platform':'ios','deviceName':'Work iPhone','appVersion':'2.3.1+45',
          });
          return _answer(req,{'accessToken':'new-access',
            'refreshToken':List<String>.filled(64,'r').join(),
            'expiresAt':futureExpiry,'mustChangePassword':false});
        }
        throw StateError('Unexpected request');
      }));
    addTearDown(gateway.dispose);
    final result=await gateway.login(
      identifier:' demo@example.test ',password:'test-password',
      platform:'ios',deviceName:' Work iPhone ',appVersion:'2.3.1+45');
    expect(result.requiresTwoFactor,true);
    expect(result.authenticated,false);
    expect(result.secondFactor!.methods, ['EMAIL_OTP','PHONE_OTP']);
    expect(session.access,isNull);
    final id=await gateway.requestSecondFactor(result.secondFactor!,
      preferredChannel:'EMAIL');
    expect(id,otpChallenge);
    expect(session.access,isNull);
    final complete=await gateway.completeSecondFactor(result.secondFactor!,
      challengeId:id,code:'123456');
    expect(complete.authenticated,true);
    expect(complete.mustChangePassword,false);
    expect(session.access,'new-access');
    expect(calls,['/auth/login','/auth/2fa/login/request','/auth/2fa/login/complete']);
  });

  test('Malformed 2FA source operation cannot receive challenge or OTP',()async{
    for(final kind in ['request','complete']){
      for(final op in <FableOperation>[
        _op('auth.2fa.login.$kind','GET','/auth/2fa/login/$kind'),
        _op('auth.2fa.login.$kind','POST','/different'),
        _op('auth.2fa.login.$kind','POST','/auth/2fa/login/$kind',protected:true),
        _op('auth.2fa.login.$kind','POST','/auth/2fa/login/$kind',enforced:false),
      ]){
        final session=_Session();
        var secretCalls=0;
        final gateway=FableAuthGateway(
          baseUri:Uri.parse('https://fable.test'),
          contract:_catalog(request:kind=='request'?op:null,
            complete:kind=='complete'?op:null),
          secureSession:session,
          client:_mock((req)async{
            if(req.path=='/auth/login')return _answer(req,{
              'requiresTwoFactor':true,'twoFactorToken':pendingToken,
              'methods':['EMAIL_OTP'],'expiresAt':futureExpiry,
            });
            secretCalls++;
            return _answer(req,{'challengeId':otpChallenge});
          }));
        final result=await gateway.login(
          identifier:'test@example.test',password:'password',platform:'android');
        if(kind=='request'){
          await expectLater(gateway.requestSecondFactor(
            result.secondFactor!),throwsStateError);
        }else{
          await expectLater(gateway.completeSecondFactor(
            result.secondFactor!,challengeId:otpChallenge,code:'123456'),
            throwsStateError);
        }
        expect(secretCalls,0);
        expect(session.access,isNull);
        gateway.dispose();
      }
    }
  });

  test('invalid device metadata fails before submitting any password',()async{
    var sent=0;
    final gateway=FableAuthGateway(
      baseUri:Uri.parse('https://fable.test'),contract:_catalog(),
      secureSession:_Session(),
      client:_mock((req)async {sent++;return _answer(req,{});}));
    addTearDown(gateway.dispose);
    for(final bad in [
      {'platform':'android\nbad'},
      {'platform':'ios','deviceName':'secret\rheader'},
      {'platform':'ios','appVersion':'1\n2'},
      {'platform':'ios','deviceName':''},
      {'platform':'ios','appVersion':List.filled(65,'x').join()},
    ]){
      await expectLater(gateway.login(identifier:'test@example.test',
        password:'password',platform:bad['platform']!,
        deviceName:bad['deviceName'],appVersion:bad['appVersion']),
        throwsArgumentError);
    }
    expect(sent,0);
  });

  test('invalid second-factor methods and unadvertised selected channel are rejected',()async{
    for(final raw in <Object?>[
      <String>[],<String>['EMAIL_OTP','EMAIL_OTP'],
      <String>['FIDO_CUSTOM'],<Object>['EMAIL_OTP',3],
    ]){
      final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
        contract:_catalog(),secureSession:_Session(),
        client:_mock((req)async=>_answer(req,{
          'requiresTwoFactor':true,'twoFactorToken':pendingToken,
          'methods':raw,'expiresAt':futureExpiry,
        })));
      await expectLater(gateway.login(identifier:'test@example.test',
        password:'password',platform:'android'),throwsFormatException);
      gateway.dispose();
    }
    var requests=0;
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_catalog(),secureSession:_Session(),
      client:_mock((req)async{
        if(req.path=='/auth/login')return _answer(req,{
          'requiresTwoFactor':true,'twoFactorToken':pendingToken,
          'methods':['EMAIL_OTP'],'expiresAt':futureExpiry,
        });
        requests++;
        return _answer(req,{});
      }));
    addTearDown(gateway.dispose);
    final login=await gateway.login(identifier:'test@example.test',
      password:'password',platform:'android');
    await expectLater(gateway.requestSecondFactor(
      login.secondFactor!,preferredChannel:'PHONE'),throwsArgumentError);
    expect(requests,0);
  });

  test('2FA completion accepts only version-four UUID challenge ids',()async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_catalog(),secureSession:_Session(),
      client:_mock((req)async=>_answer(req,{
        'requiresTwoFactor':true,'twoFactorToken':pendingToken,
        'methods':['EMAIL_OTP'],'expiresAt':futureExpiry,
      })));
    addTearDown(gateway.dispose);
    final login=await gateway.login(identifier:'test@example.test',
      password:'password',platform:'android');
    await expectLater(gateway.completeSecondFactor(login.secondFactor!,
      challengeId:'550e8400-e29b-1414-8466-446655440000',
      code:'123456'),throwsArgumentError);
  });
}
