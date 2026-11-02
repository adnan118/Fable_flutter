import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/fable_auth.dart';

FableContract _contract()=>FableContract(
  contractHash:'rc97',projectName:'test',selectionMode:'advisory',
  featureIds:const {'auth'},operations:{
    'auth.username.availability':const FableOperation(
      'auth.username.availability','GET',
      '/auth/me/username/availability/:username','rc97',enforceAuth:true),
    'auth.username.update':const FableOperation(
      'auth.username.update','PATCH','/auth/me/username','rc97',enforceAuth:true),
    'auth.otp.public.request':const FableOperation(
      'auth.otp.public.request','POST','/auth/otp/public/request','rc97',
      requiresAuth:false,enforceAuth:true),
    'auth.otp.public.verify':const FableOperation(
      'auth.otp.public.verify','POST','/auth/otp/public/verify','rc97',
      requiresAuth:false,enforceAuth:true),
    'auth.otp.login.complete':const FableOperation(
      'auth.otp.login.complete','POST','/auth/otp/login/complete','rc97',
      requiresAuth:false,enforceAuth:true),
  });

void main(){
  testWidgets('RC97 Username screen exposes only confirmed Fable operations',
      (tester)async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://test.invalid'),
      contract:_contract());
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(
      home:FableUsernameSettingsPage(gateway:gateway)));
    expect(find.text('Check availability'),findsOneWidget);
    expect(find.text('Save username'),findsOneWidget);
  });

  testWidgets('RC97 public LOGIN OTP is separated from password reset',
      (tester)async{
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://test.invalid'),
      contract:_contract());
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(
      home:FableOtpLoginPage(gateway:gateway)));
    expect(find.text('Sign in with OTP'),findsOneWidget);
    expect(find.text('Request login OTP'),findsOneWidget);
    expect(find.text('Reset password'),findsNothing);
  });
}
