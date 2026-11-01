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
}
