import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/src/change_password_page.dart';

FableContract _catalog(bool enabled)=>FableContract(
 contractHash:List<String>.filled(64,'a').join(),projectName:'fable-ui-test',
 selectionMode:'explicit',featureIds:const <String>{},
 operations:enabled?const {
 'auth.change-password':FableOperation('auth.change-password',
   'POST','/auth/change-password','hash',requiresAuth:true,enforceAuth:true),
 }:const <String,FableOperation>{},
);
void main(){
 testWidgets('no password change UI for a Backend lacking the operation', (tester)async{
   final contract=_catalog(false);
   final gateway=FableAuthGateway(
     baseUri:Uri.parse('https://api.example.test'),contract:contract);
   addTearDown(gateway.dispose);
   await tester.pumpWidget(MaterialApp(home:
     FableChangePasswordPage(gateway:gateway,contract:contract)));
   expect(find.text('Password change is not provided by this Backend contract.'),
     findsOneWidget);
   expect(find.text('Current password'),findsNothing);
   expect(find.text('Change password and sign out'),findsNothing);
 });
 testWidgets('password mismatch is rejected locally before any network call',(tester)async{
   final contract=_catalog(true);
   final gateway=FableAuthGateway(
     baseUri:Uri.parse('https://api.example.test'),contract:contract);
   addTearDown(gateway.dispose);
   await tester.pumpWidget(MaterialApp(home:
     FableChangePasswordPage(gateway:gateway,contract:contract)));
   expect(find.textContaining('All signed-in devices'),findsOneWidget);
   await tester.enterText(find.widgetWithText(TextFormField,'Current password'),
     'initial-secret');
   await tester.enterText(find.widgetWithText(TextFormField,'New password'),
     'new-secret-value');
   await tester.enterText(find.widgetWithText(TextFormField,'Confirm new password'),
     'does-not-match');
   await tester.ensureVisible(find.text('Change password and sign out'));
   await tester.tap(find.text('Change password and sign out'));
   await tester.pump();
   expect(find.text('Passwords do not match'),findsOneWidget);
 });
}
