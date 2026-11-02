import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/fable_auth.dart';

class _Session extends FableSecureSession {
  @override int identityRevision=0;
  @override Future<String?> get accessToken async=>'test-rc93-token';
  @override Future<String?> get refreshToken async=>null;
  @override Future<String> installationId()async=>'abcdefabcdefabcdefabcdefabcdefab';
}
FableContract _contract(bool enabled)=>FableContract(
  contractHash:'hash',projectName:'rc93',selectionMode:'advisory',
  featureIds:const <String>{'auth'},
  operations:enabled?{
    for(final pair in [
      ['auth.2fa.status','GET','/auth/2fa/status'],
      ['auth.2fa.enable','POST','/auth/2fa/enable'],
      ['auth.2fa.disable','POST','/auth/2fa/disable'],
      ['auth.otp.request','POST','/auth/otp/request'],
      ['auth.otp.verify','POST','/auth/otp/verify'],
      ['auth.contact.email.change','POST','/auth/contact/email/change'],
      ['auth.contact.phone.change','POST','/auth/contact/phone/change'],
    ])
      pair[0]:FableOperation(pair[0],pair[1],pair[2],'hash',
        requiresAuth:true,enforceAuth:true),
  }:<String,FableOperation>{},
);

void main(){
  testWidgets('RC93 2FA/contact controls not exposed without verified Fable contract',
    (tester)async{
      final gateway=FableAuthGateway(
        baseUri:Uri.parse('https://api.fable.test'),
        contract:_contract(false),secureSession:_Session());
      addTearDown(gateway.dispose);
      await tester.pumpWidget(MaterialApp(
        home:FableSecuritySettingsPage(gateway:gateway)));
      await tester.pump();
      expect(find.text('Enable 2FA'),findsNothing);
      expect(find.text('Change email'),findsNothing);
      expect(find.text('Change phone'),findsNothing);
      expect(find.text('2FA status not verified'),findsOneWidget);
    });
  testWidgets('RC93 renders only source-verified actions and requests OTP after selecting',
    (tester)async{
      final dio=Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest:(req,handler){
        if(req.path=='/auth/2fa/status'){
          handler.resolve(Response<dynamic>(requestOptions:req,statusCode:200,
            data:{'enabled':false,'enabledAt':null,
              'methods':['EMAIL_OTP']}));
        }else{
          handler.resolve(Response<dynamic>(requestOptions:req,statusCode:200,
            data:{}));
        }
      }));
      final gateway=FableAuthGateway(
        baseUri:Uri.parse('https://api.fable.test'),contract:_contract(true),
        secureSession:_Session(),client:dio);
      addTearDown(gateway.dispose);
      await tester.pumpWidget(MaterialApp(
        home:FableSecuritySettingsPage(gateway:gateway)));
      await tester.pumpAndSettle();
      expect(find.text('2FA disabled'),findsOneWidget);
      expect(find.text('Enable 2FA'),findsOneWidget);
      expect(find.text('Change email'),findsOneWidget);
      expect(find.text('Change phone'),findsOneWidget);
      await tester.tap(find.text('Enable 2FA'));
      await tester.pump();
      expect(find.text('Selected: TWO_FACTOR'),findsOneWidget);
      expect(find.text('Request OTP'),findsOneWidget);
      expect(find.text('Confirm security change'),findsNothing);
    });
}
