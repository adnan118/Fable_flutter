import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/src/login_page.dart';

/// لا تُعرض بيانات الأجهزة عند تلقي mustChangePassword من الخادم.
/// نحقن Gateway حقيقية بعقد Fable وTransport اختباري؛ لا نختلق Backend خارجي.
class _Session extends FableSecureSession {
  String? access;
  String? refresh;
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>access;
  @override Future<String?> get refreshToken async=>refresh;
  @override Future<String> installationId()async=>
    '0123456789abcdef0123456789abcdef';
  @override Future<bool> replaceTokensIfIdentity({
    required int expectedIdentity,required String accessToken,
    String? refreshToken})async{
    if(expectedIdentity!=identityRevision)return false;
    access=accessToken;refresh=refreshToken;identityRevision++;
    return true;
  }
}
FableContract _contract()=>FableContract(
  contractHash:List<String>.filled(64,'a').join(),
  projectName:'rc84',selectionMode:'explicit',
  featureIds:const {'auth'},
  operations:const {
    'auth.login':FableOperation('auth.login','POST','/auth/login','hash',
      requiresAuth:false,enforceAuth:true),
    'auth.sessions':FableOperation('auth.sessions','GET','/auth/sessions','hash',
      requiresAuth:true,enforceAuth:true),
    'auth.change-password':FableOperation('auth.change-password',
      'POST','/auth/change-password','hash',requiresAuth:true,enforceAuth:true),
  },
);
Dio _network(Response<dynamic> Function(RequestOptions) response){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,h) {
    h.resolve(response(req));
  }));
  return dio;
}
Response<dynamic> _response(RequestOptions req,int status,Object? data)=>
  Response(requestOptions:req,statusCode:status,data:data);
Dio _delayedNetwork(Future<Response<dynamic>> Function(RequestOptions) response){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(req,h)async{
    try{h.resolve(await response(req));}
    catch(error){h.reject(DioException(requestOptions:req,error:error));}
  }));
  return dio;
}

void main(){
  for(final mustChange in [true,false]){
    testWidgets('Login screen gates normal operations when mustChangePassword=$mustChange',(tester)async{
      final session=_Session();
      final gateway=FableAuthGateway(
        baseUri:Uri.parse('https://fable.test'),
        contract:_contract(),
        secureSession:session,
        client:_network((req)=>_response(req,200,{
          'accessToken':'token',
          'refreshToken':List<String>.filled(64,'r').join(),
          'expiresAt':'2099-01-01T00:00:00Z',
          'mustChangePassword':mustChange,
        })));
      addTearDown(gateway.dispose);
      await tester.pumpWidget(MaterialApp(home:FableLoginPage(
        contract:_contract(),gateway:gateway)));
      await tester.pumpAndSettle();
      final fields=find.byType(TextFormField);
      expect(fields,findsNWidgets(2));
      await tester.enterText(fields.at(0),'test@example.test');
      await tester.enterText(fields.at(1),'password-for-tests');
      await tester.tap(find.widgetWithText(FilledButton,'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'),findsOneWidget);
      expect(find.text('My active devices & sessions'),
        mustChange?findsNothing:findsOneWidget);
      expect(find.text('Change password to continue'),
        mustChange?findsOneWidget:findsNothing);
      expect(find.textContaining('Password change required'),
        mustChange?findsOneWidget:findsNothing);
    });
  }

  testWidgets('Saved session with AUTH_PASSWORD_CHANGE_REQUIRED keeps tokens but locks features',(tester)async{
    final session=_Session()
      ..access='saved-token'
      ..refresh=List<String>.filled(64,'r').join();
    final gateway=FableAuthGateway(
      baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,
      client:_network((req)=>_response(req,403,{
        'code':'AUTH_PASSWORD_CHANGE_REQUIRED',
      })));
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FableLoginPage(
      contract:_contract(),gateway:gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Verify saved session'),findsOneWidget);
    await tester.tap(find.text('Verify saved session'));
    await tester.pumpAndSettle();
    expect(find.text('Change password to continue'),findsOneWidget);
    expect(find.text('My active devices & sessions'),findsNothing);
    expect(session.access,'saved-token');
  });
  testWidgets('RC214 late rejected login must not display an error for another account',
      (tester)async{
    final session=_Session();
    final reached=Completer<void>(),resume=Completer<void>();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,
      client:_delayedNetwork((req)async{
        if(req.path=='/auth/login'){
          reached.complete();await resume.future;
          // Malformed old login cannot write any new authenticated identity.
          return _response(req,200,{'data':{'requiresTwoFactor':true}});
        }
        return _response(req,404,{});
      }));
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FableLoginPage(
      contract:_contract(),gateway:gateway)));
    await tester.pumpAndSettle();
    final fields=find.byType(TextFormField);
    await tester.enterText(fields.at(0),'old-login@example.test');
    await tester.enterText(fields.at(1),'old-password');
    await tester.tap(find.widgetWithText(FilledButton,'Sign in'));
    await tester.pump();
    await reached.future;
    expect(await session.replaceTokensIfIdentity(expectedIdentity:0,
      accessToken:'new-account-token'),true);
    resume.complete();
    await tester.pumpAndSettle();
    expect(session.access,'new-account-token');
    expect(find.text('Sign-in failed. Check contract and backend connection.'),findsNothing);
    expect(find.text('Session saved securely.'),findsNothing);
  });

  testWidgets('RC214 stale saved-session verification unlocks the screen after identity switch',
      (tester)async{
    final session=_Session()..access='saved-old-token';
    final reached=Completer<void>(),resume=Completer<void>();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,
      client:_delayedNetwork((req)async{
        if(req.path=='/auth/sessions'){
          reached.complete();await resume.future;
          return _response(req,200,{'data':[]});
        }
        return _response(req,404,{});
      }));
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FableLoginPage(
      contract:_contract(),gateway:gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Verify saved session'),findsOneWidget);
    await tester.tap(find.text('Verify saved session'));
    await tester.pump();
    await reached.future;
    expect(await session.replaceTokensIfIdentity(expectedIdentity:0,
      accessToken:'new-account-token'),true);
    resume.complete();
    await tester.pumpAndSettle();
    expect(find.text('Your saved session was verified by the server.'),findsNothing);
    final verify=tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton,'Verify saved session'));
    expect(verify.onPressed,isNotNull,
      reason:'A discarded old response must not permanently lock verification');
    expect(session.access,'new-account-token');
  });

  testWidgets('RC214 late old logout never claims sign-out or deletes a new account',
      (tester)async{
    final session=_Session()..access='saved-old-token';
    final reached=Completer<void>(),resume=Completer<void>();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.test'),
      contract:_contract(),secureSession:session,
      client:_delayedNetwork((req)async{
        if(req.path=='/auth/sessions')return _response(req,200,{'data':[]});
        if(req.path=='/auth/logout'){
          reached.complete();await resume.future;
          return _response(req,200,{'data':{'revoked':true}});
        }
        return _response(req,404,{});
      }));
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FableLoginPage(
      contract:_contract(),gateway:gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify saved session'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'),findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await reached.future;
    expect(await session.replaceTokensIfIdentity(expectedIdentity:0,
      accessToken:'new-account-token'),true);
    resume.complete();
    await tester.pumpAndSettle();
    expect(session.access,'new-account-token');
    expect(find.text('Signed out of this session.'),findsNothing);
    expect(find.text('Local credentials removed. Server revocation could not be confirmed.'),
      findsNothing);
    expect(find.text('Session changed during sign-out. Verify the current session.'),
      findsOneWidget);
    expect(find.text('Verify saved session'),findsOneWidget);
  });

}
