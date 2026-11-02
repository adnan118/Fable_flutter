import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/fable_auth.dart';
import 'package:fable_auth/src/login_page.dart';

FableContract resetContract({bool exact=true})=>FableContract(
  contractHash:'hash',projectName:'rc91',selectionMode:'advisory',
  featureIds:const <String>{'auth'},
  operations:{
    'auth.otp.public.request':FableOperation('auth.otp.public.request','POST',
      exact?'/auth/otp/public/request':'/auth/otp/request','hash',
      requiresAuth:false,enforceAuth:true),
    'auth.otp.public.verify':const FableOperation('auth.otp.public.verify','POST',
      '/auth/otp/public/verify','hash',requiresAuth:false,enforceAuth:true),
    'auth.password.reset':const FableOperation('auth.password.reset','POST',
      '/auth/password/reset','hash',requiresAuth:false,enforceAuth:true),
  });

void main(){
  testWidgets('Password reset page refuses missing/mismatched public Fable contract',
      (tester)async{
    final contract=resetContract(exact:false);
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.example.test'),
      contract:contract);
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(home:FablePasswordResetPage(gateway:gateway)));
    expect(find.textContaining('no verified public OTP'),findsOneWidget);
    expect(find.text('Request reset code'),findsNothing);
  });
  testWidgets('Login shows the Fable public OTP reset entry only on exact contract',
      (tester)async{
    final contract=resetContract();
    final gateway=FableAuthGateway(baseUri:Uri.parse('https://fable.example.test'),
      contract:contract);
    addTearDown(gateway.dispose);
    await tester.pumpWidget(MaterialApp(
      home:FableLoginPage(contract:contract,gateway:gateway)));
    expect(find.text('Forgot password? Verify by OTP'),findsOneWidget);
    // The reset action is below the first fold on the standard 800x600
    // widget-test viewport. Scroll the actual ListView before tapping.
    await tester.drag(find.byType(ListView).first,const Offset(0,-260));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forgot password? Verify by OTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password? Verify by OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Password recovery'),findsOneWidget);
    expect(find.text('Request reset code'),findsOneWidget);
    expect(find.text('Sign in'),findsNothing);
  });
}
