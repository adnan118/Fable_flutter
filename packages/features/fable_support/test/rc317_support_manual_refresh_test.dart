import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_support/fable_support.dart';

class _Catalog implements OperationCatalog {
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>
      const {'tickets.list','tickets.create'}.contains(id);
  @override FableOperation require(String id){
    if(id=='tickets.list')return const FableOperation(
      'tickets.list','GET','/support/tickets','source',
      requiresAuth:true,enforceAuth:true,
    );
    if(id=='tickets.create')return const FableOperation(
      'tickets.create','POST','/support/tickets','source',
      requiresAuth:true,enforceAuth:true,
    );
    throw StateError('Unknown operation');
  }
}
class _NoGateway implements BackendApiGateway {
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Encoder implements FableSupportRequestEncoder {
  @override Map<String,dynamic> encode({
    required String subject,required String description,
  })=>{'subject':subject,'description':description};
}
class _Repository extends FableSupportRepository {
  _Repository():super(
    gateway:_NoGateway(),
    operations:FableSupportOperations.fromContract(
      _Catalog(),listOperationId:'tickets.list',createOperationId:'tickets.create',
    ),
    decodeList:(_)=>[],encoder:_Encoder(),
  );
  int reads=0;
  Future<List<FableSupportTicket>> Function()? next;
  @override Future<List<FableSupportTicket>> list(){
    reads++;
    return next?.call()??Future.value(<FableSupportTicket>[]);
  }
}
FableSupportTicket _ticket(String subject)=>FableSupportTicket.fromJson({
  'id':'ticket-source','subject':subject,'status':'OPEN',
});
void main(){
  testWidgets('RC317 failed ticket load offers explicit identity-safe Try again',
      (tester)async{
    final repo=_Repository();
    final events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    repo.next=()=>Future.error(StateError('offline'));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FableSupportTicketList(
      repository:repo,identityRevision:()=>7,isAuthenticated:()=>true,
      identityInvalidations:events.stream,
    ))));
    await tester.pumpAndSettle();
    expect(repo.reads,1);
    expect(find.text('Try again'),findsOneWidget);
    repo.next=()=>Future.value([_ticket('Confirmed current ticket')]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.reads,2);
    expect(find.text('Confirmed current ticket'),findsOneWidget);
    expect(find.text('Refresh'),findsOneWidget);
  });

  testWidgets('RC317 refresh cannot fetch under a silently changed account',
      (tester)async{
    final repo=_Repository();
    final events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    var revision=1;
    repo.next=()=>Future.value([_ticket('Original private ticket')]);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FableSupportTicketList(
      repository:repo,identityRevision:()=>revision,isAuthenticated:()=>true,
      identityInvalidations:events.stream,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Original private ticket'),findsOneWidget);
    revision=2; // event may be delayed
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(repo.reads,1);
    expect(find.text('Original private ticket'),findsNothing);
    expect(find.textContaining('Session changed'),findsOneWidget);
  });

  testWidgets('RC317 an older refresh response cannot replace newer tickets',
      (tester)async{
    final repo=_Repository();
    final events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    final oldRead=Completer<List<FableSupportTicket>>();
    repo.next=()=>Future.value([_ticket('First current ticket')]);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FableSupportTicketList(
      repository:repo,identityRevision:()=>11,isAuthenticated:()=>true,
      identityInvalidations:events.stream,
    ))));
    await tester.pumpAndSettle();
    repo.next=()=>oldRead.future;
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    repo.next=()=>Future.value([_ticket('Newest ticket')]);
    events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Newest ticket'),findsOneWidget);
    oldRead.complete([_ticket('STALE PRIVATE TICKET')]);
    await tester.pumpAndSettle();
    expect(find.text('STALE PRIVATE TICKET'),findsNothing);
    expect(find.text('Newest ticket'),findsOneWidget);
  });
}
