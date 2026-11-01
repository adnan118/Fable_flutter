import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_auth/src/sessions_page.dart';

FableContract _contract({required bool timezone})=>FableContract(
  contractHash:List<String>.filled(64,'a').join(),
  projectName:'rc82-ui',selectionMode:'explicit',
  featureIds:const <String>{},
  operations:{
    if(timezone)'auth.session.timezone':const FableOperation(
      'auth.session.timezone','POST','/auth/session/timezone','hash',
      requiresAuth:true,enforceAuth:true),
  },
);

void main(){
 testWidgets('session timezone controls remain absent for a non-exported operation',
 (tester)async{
   final contract=_contract(timezone:false);
   final gateway=FableAuthGateway(
     baseUri:Uri.parse('https://fable.test'),contract:contract);
   addTearDown(gateway.dispose);
   await tester.pumpWidget(MaterialApp(home:
     FableSessionsPage(gateway:gateway,contract:contract)));
   await tester.pumpAndSettle();
   expect(find.text('Save session time zone'),findsNothing);
   expect(find.text('Session time zone (IANA)'),findsNothing);
 });
 testWidgets('explicit Fable timezone operation shows native input and server-authoritative hint',
 (tester)async{
   final contract=_contract(timezone:true);
   final gateway=FableAuthGateway(
     baseUri:Uri.parse('https://fable.test'),contract:contract);
   addTearDown(gateway.dispose);
   await tester.pumpWidget(MaterialApp(home:
     FableSessionsPage(gateway:gateway,contract:contract)));
   await tester.pumpAndSettle();
   expect(find.text('Save session time zone'),findsOneWidget);
   expect(find.text('Session time zone (IANA)'),findsOneWidget);
   expect(find.textContaining('does not change scheduling'),findsOneWidget);
 });
}
