import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_access_control/fable_access_control.dart';

Map<String, dynamic> manifest(String provider) => {
  'schemaVersion':1, 'kind':'fable.mobile-access-policy',
  'provider':provider, 'contractFingerprint':'verified-hash',
  'operations':{
    'docs.open':{'mode':'public'},
    'docs.manage':{'mode':'permissions','keys':['docs.manage']},
    'docs.private':{'mode':'authenticated'},
  },
};

void main() {
  for (final backend in ['fable','other']) {
    test('$backend: UI access is declarative and denies unmapped operations', () {
      final policy=FableAccessPolicy.fromManifest(manifest(backend),
          expectedFingerprint:'verified-hash');
      final user=FableAccessSnapshot.fromJson({
        'userId':'u1','keys':['docs.read'],'roles':['admin']
      });
      expect(policy.allows('docs.open',null),true);
      expect(policy.allows('docs.private',null),false);
      expect(policy.allows('docs.private',user),true);
      expect(policy.allows('docs.manage',user),false); // admin != implicit grant
      expect(policy.allows('docs.missing',user),false);
      expect(() => FableAccessPolicy.fromManifest(manifest(backend),
          expectedFingerprint:'stale'), throwsFormatException);
    });
  }
  testWidgets('scope reacts automatically to revocation and sign out', (tester) async {
    final snapshot=ValueNotifier<FableAccessSnapshot?>(null);
    final policy=FableAccessPolicy.fromManifest(manifest('other'));
    await tester.pumpWidget(FableAccessScope(policy:policy,snapshot:snapshot,
      child:const Directionality(textDirection:TextDirection.ltr,child:Column(children:[
        FableOperationVisibility(operationId:'docs.manage',child:Text('manage')),
        FableOperationVisibility(operationId:'docs.open',child:Text('public')),
      ]))));
    expect(find.text('manage'), findsNothing);
    expect(find.text('public'), findsOneWidget);
    snapshot.value=FableAccessSnapshot.fromJson({
      'userId':'u1','keys':['docs.manage'],'roles':[]
    });
    await tester.pump();
    expect(find.text('manage'), findsOneWidget);
    snapshot.value=null;
    await tester.pump();
    expect(find.text('manage'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    snapshot.dispose();
  });
  testWidgets('action widget gates operations automatically', (tester) async {
    final snapshot=ValueNotifier<FableAccessSnapshot?>(null);
    final policy=FableAccessPolicy.fromManifest(manifest('fable'));
    await tester.pumpWidget(FableAccessScope(policy:policy,snapshot:snapshot,
      child:MaterialApp(home:Scaffold(body:Column(children:[
        FableAuthorizedAsyncButton(operationId:'docs.manage',label:'Manage',onExecute:() async {}),
        FableAuthorizedAsyncButton(operationId:'docs.open',label:'Open',onExecute:() async {}),
      ])))));
    expect(find.text('Manage'),findsNothing);
    expect(find.text('Open'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    snapshot.dispose();
  });
  testWidgets('missing scope never exposes a private component', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection:TextDirection.ltr,
      child:FableOperationVisibility(operationId:'docs.manage',child:Text('manage'))));
    expect(find.text('manage'),findsNothing);
  });
}
