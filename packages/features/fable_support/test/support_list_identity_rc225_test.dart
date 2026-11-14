import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_support/fable_support.dart';

class _Catalog implements OperationCatalog {
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>const {'tickets.list','tickets.create'}.contains(id);
  @override FableOperation require(String id){
    if(id=='tickets.list')return const FableOperation('tickets.list','GET',
      '/support/tickets','test',requiresAuth:true,enforceAuth:true);
    if(id=='tickets.create')return const FableOperation('tickets.create','POST',
      '/support/tickets','test',requiresAuth:true,enforceAuth:true);
    throw StateError('Unknown support operation');
  }
}
class _NotUsedGateway implements BackendApiGateway {
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Encoder implements FableSupportRequestEncoder {
  @override Map<String,dynamic> encode({
    required String subject,required String description,
  })=>{'subject':subject,'description':description};
}
class _SupportRepo extends FableSupportRepository {
  _SupportRepo():super(gateway:_NotUsedGateway(),
    operations:FableSupportOperations.fromContract(_Catalog(),
      listOperationId:'tickets.list',createOperationId:'tickets.create'),
    decodeList:(_)=>[],encoder:_Encoder());
  Future<List<FableSupportTicket>> Function()? load;
  int reads=0;
  @override Future<List<FableSupportTicket>> list(){
    reads++;
    return load?.call()??Future.value(<FableSupportTicket>[]);
  }
}
FableSupportTicket _ticket(String title)=>FableSupportTicket.fromJson({
  'id':'ticket-private','subject':title,'status':'OPEN',
});
Future<void> _mount(WidgetTester tester,_SupportRepo repo,Stream<void> events,
    int Function() revision,bool Function() authenticated)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(
    body:FableSupportTicketList(repository:repo,identityRevision:revision,
      isAuthenticated:authenticated,identityInvalidations:events),
  )));
}
void main(){
  testWidgets('RC225 legacy standalone ticket list without identity bindings fails closed',
      (tester)async{
    final repo=_SupportRepo();
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:FableSupportTicketList(repository:repo))));
    await tester.pumpAndSettle();
    expect(repo.reads,0);
    expect(find.textContaining('authenticated session'),findsOneWidget);
  });

  testWidgets('RC225 a verified current user may view only its bound support data',
      (tester)async{
    final repo=_SupportRepo(),events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    repo.load=()=>Future.value([_ticket('Current user ticket')]);
    await _mount(tester,repo,events.stream,()=>1,()=>true);
    await tester.pumpAndSettle();
    expect(repo.reads,1);
    expect(find.text('Current user ticket'),findsOneWidget);
  });

  testWidgets('RC225 old async ticket response never overwrites a new account',
      (tester)async{
    final repo=_SupportRepo(),events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    final previous=Completer<List<FableSupportTicket>>();
    repo.load=()=>previous.future;
    var epoch=4;
    int revision()=>epoch;
    bool authenticated()=>true;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pump();
    expect(repo.reads,1);
    repo.load=()=>Future.value([_ticket('New account ticket')]);
    epoch=5;
    events.add(null);
    await tester.pumpAndSettle();
    expect(repo.reads,2);
    expect(find.text('New account ticket'),findsOneWidget);
    previous.complete([_ticket('OLD ACCOUNT PRIVATE TICKET')]);
    await tester.pumpAndSettle();
    expect(find.text('OLD ACCOUNT PRIVATE TICKET'),findsNothing);
    expect(find.text('New account ticket'),findsOneWidget);
  });

  testWidgets('RC225 silent account switch hides old ticket without relying on event',
      (tester)async{
    final repo=_SupportRepo(),events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    repo.load=()=>Future.value([_ticket('Old user private request')]);
    var epoch=11;
    int revision()=>epoch;
    bool authenticated()=>true;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pumpAndSettle();
    expect(find.text('Old user private request'),findsOneWidget);
    epoch=12;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pumpAndSettle();
    expect(find.text('Old user private request'),findsNothing);
    expect(find.textContaining('Session changed'),findsOneWidget);
  });

  testWidgets('RC225 revoked authentication hides visible support tickets immediately on rebuild',
      (tester)async{
    final repo=_SupportRepo(),events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    repo.load=()=>Future.value([_ticket('Sensitive support ticket')]);
    var authorized=true;
    int revision()=>20;
    bool authenticated()=>authorized;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pumpAndSettle();
    expect(find.text('Sensitive support ticket'),findsOneWidget);
    authorized=false;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pumpAndSettle();
    expect(find.text('Sensitive support ticket'),findsNothing);
    expect(find.textContaining('Sign in'),findsOneWidget);
  });

  testWidgets('RC225 sign-out does not initiate a new support read',
      (tester)async{
    final repo=_SupportRepo(),events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    var authorized=false;
    int revision()=>30;
    bool authenticated()=>authorized;
    await _mount(tester,repo,events.stream,revision,authenticated);
    await tester.pumpAndSettle();
    expect(repo.reads,0);
    events.add(null);
    await tester.pumpAndSettle();
    expect(repo.reads,0);
    authorized=true;
    events.add(null);
    await tester.pumpAndSettle();
    expect(repo.reads,1);
  });
}
