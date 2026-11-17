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
      'tickets.list','GET','/support/tickets',
      'source',requiresAuth:true,enforceAuth:true);
    if(id=='tickets.create')return const FableOperation(
      'tickets.create','POST','/support/tickets',
      'source',requiresAuth:true,enforceAuth:true);
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
      _Catalog(),listOperationId:'tickets.list',
      createOperationId:'tickets.create',
    ),
    decodeList:(_)=>[],encoder:_Encoder(),
  );
  int reads=0;
  @override Future<List<FableSupportTicket>> list() async{
    reads++;
    return <FableSupportTicket>[];
  }
}
void main(){
  testWidgets('RC340 throwing authentication provider cannot issue private ticket GET',
      (tester)async{
    final events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    final repo=_Repository();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FableSupportTicketList(
      repository:repo,identityInvalidations:events.stream,
      identityRevision:()=>1,isAuthenticated:()=>throw StateError('unavailable'),
    ))));
    await tester.pump();
    expect(repo.reads,0);
    expect(find.textContaining('Sign in or verify'),findsOneWidget);
  });

  testWidgets('RC340 throwing revision callback cannot disclose a stale support list',
      (tester)async{
    final events=StreamController<void>.broadcast(sync:true);
    addTearDown(events.close);
    final repo=_Repository();
    var failRevision=false;
    int revision(){
      if(failRevision)throw StateError('revision unavailable');
      return 1;
    }
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FableSupportTicketList(
      repository:repo,identityInvalidations:events.stream,
      identityRevision:revision,isAuthenticated:()=>true,
    ))));
    await tester.pumpAndSettle();
    expect(repo.reads,1);
    failRevision=true;
    events.add(null);
    await tester.pumpAndSettle();
    expect(repo.reads,1);
    expect(find.textContaining('Sign in or verify'),findsOneWidget);
    expect(find.text('Refresh'),findsNothing);
  });
}
