import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_support/fable_support.dart';

class _Support implements FableSupportWorkflowPort {
  Future<List<FableSupportTicket>> Function()? load;
  Future<void> Function(String subject,String description)? submit;
  int reads=0,writes=0;
  @override Future<List<FableSupportTicket>> list() {
    reads++;
    return load?.call() ?? Future.value([]);
  }
  @override Future<void> create({required String subject,required String description}) {
    writes++;
    return submit?.call(subject,description) ?? Future.value();
  }
}
FableSupportTicket _ticket(String subject)=>FableSupportTicket.fromJson({
  'id':'ticket-1','subject':subject,'status':'OPEN',
});
Future<void> _mount(WidgetTester tester,_Support repo,Stream<void> changes,
    int Function() revision,bool Function() authenticated) async {
  await tester.pumpWidget(MaterialApp(home:FableSupportWorkflowPage(
    repository:repo,identityRevision:revision,
    isAuthenticated:authenticated,identityInvalidations:changes,
  )));
}
void main(){
  testWidgets('RC144 Support never fetches or mutates for unauthenticated account',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      await _mount(tester,repo,changes.stream,()=>1,()=>false);
      expect(repo.reads,0);
      expect(repo.writes,0);
      expect(tester.widget<FilledButton>(find.byKey(const Key('support-create'))).onPressed,isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('support-load'))).onPressed,isNull);
      await changes.close();
    });
  testWidgets('RC144 verified repository supplies visible tickets only after load',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      repo.load=()=>Future.value([_ticket('Billing question')]);
      await _mount(tester,repo,changes.stream,()=>1,()=>true);
      expect(find.text('Billing question'),findsNothing);
      await tester.tap(find.byKey(const Key('support-load')));
      await tester.pumpAndSettle();
      expect(find.text('Billing question'),findsOneWidget);
      expect(repo.reads,1);
      await changes.close();
    });
  testWidgets('RC144 account switch clears tickets and discards stale responses',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      final pending=Completer<List<FableSupportTicket>>();
      repo.load=()=>pending.future;
      var epoch=1;
      await _mount(tester,repo,changes.stream,()=>epoch,()=>true);
      await tester.tap(find.byKey(const Key('support-load')));
      await tester.pump();
      epoch=2;
      changes.add(null);
      await tester.pump();
      pending.complete([_ticket('OLD ACCOUNT PRIVATE TICKET')]);
      await tester.pumpAndSettle();
      expect(find.text('OLD ACCOUNT PRIVATE TICKET'),findsNothing);
      expect(repo.reads,1);
      await changes.close();
    });
  testWidgets('RC144 a silent identity or authorization change hides old tickets',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      final stream=changes.stream;
      var epoch=1,authorized=true;
      int revision()=>epoch;
      bool authenticated()=>authorized;
      repo.load=()=>Future.value([_ticket('Private support record')]);
      await _mount(tester,repo,stream,revision,authenticated);
      await tester.tap(find.byKey(const Key('support-load')));
      await tester.pumpAndSettle();
      expect(find.text('Private support record'),findsOneWidget);
      // No explicit identity invalidation event; build itself must fence data.
      epoch=2;
      await _mount(tester,repo,stream,revision,authenticated);
      await tester.pumpAndSettle();
      expect(find.text('Private support record'),findsNothing);
      authorized=false;
      await _mount(tester,repo,stream,revision,authenticated);
      await tester.pumpAndSettle();
      expect(find.text('Private support record'),findsNothing);
      expect(tester.widget<OutlinedButton>(
        find.byKey(const Key('support-load'))).onPressed,isNull);
      await changes.close();
    });
  testWidgets('RC144 user-submitted support request never auto-retries',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      repo.submit=(subject,description)async{
        expect(subject,'Login access');
        expect(description,'Please review my login issue');
      };
      await _mount(tester,repo,changes.stream,()=>1,()=>true);
      await tester.enterText(find.byKey(const Key('support-subject')),'Login access');
      await tester.enterText(find.byKey(const Key('support-description')),
        'Please review my login issue');
      await tester.tap(find.byKey(const Key('support-create')));
      await tester.pumpAndSettle();
      expect(repo.writes,1);
      expect(repo.reads,0);
      expect(find.textContaining('Ticket request accepted'),findsOneWidget);
      await changes.close();
    });
  testWidgets('RC144 uncertain response refuses success or automatic replay',
    (tester)async{
      final repo=_Support(), changes=StreamController<void>.broadcast(sync:true);
      repo.submit=(_,__)async=>throw StateError('network timeout');
      await _mount(tester,repo,changes.stream,()=>1,()=>true);
      await tester.enterText(find.byKey(const Key('support-subject')),'Help needed');
      await tester.enterText(find.byKey(const Key('support-description')),
        'The app cannot load my account');
      await tester.tap(find.byKey(const Key('support-create')));
      await tester.pumpAndSettle();
      expect(repo.writes,1);
      expect(find.textContaining('Submission is unconfirmed'),findsOneWidget);
      await changes.close();
    });
}
