import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_payments/fable_payments.dart';

const firstId='550e8400-e29b-41d4-a716-446655440001';
const secondId='550e8400-e29b-41d4-a716-446655440002';

class _Catalog implements OperationCatalog {
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>id=='read';
  @override FableOperation require(String id){
    if(id!='read')throw StateError('Unsupported payment operation');
    return const FableOperation(
      'read','GET','/financial/payments/{id}','hash',
      requiresAuth:true,enforceAuth:true,
    );
  }
}

class _ControlledGateway implements BackendApiGateway {
  int calls=0;
  final pending=<Completer<Response<dynamic>>>[];
  @override Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path, Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  }){
    calls++;
    expect(operationId,'read');
    expect(body,isNull);
    final c=Completer<Response<dynamic>>();
    pending.add(c);
    return c.future;
  }
  void complete(int index,String id,String status){
    pending[index].complete(Response<dynamic>(
      requestOptions:RequestOptions(path:'/financial/payments'),
      statusCode:200,data:{'id':id,'status':status},
    ));
  }
  @override void dispose(){}
}

FablePaymentReadRepository _repo(_ControlledGateway gateway)=>
    FablePaymentReadRepository(
      gateway:gateway,operations:FablePaymentOperations.fromContract(
        _Catalog(),'read'),decode:FablePaymentSnapshot.fromJson,
    );

void main(){
  testWidgets('RC316 legacy unverified payment widget sends no HTTP', (tester)async{
    final gateway=_ControlledGateway();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      FablePaymentStatusCard(repository:_repo(gateway),paymentId:firstId),
    )));
    expect(gateway.calls,0);
    expect(find.text('A verified payment session is required.'),findsOneWidget);
  });

  testWidgets('RC316 old account payment cannot appear after A-B-A epoch', (tester)async{
    final gateway=_ControlledGateway();
    final invalidations=StreamController<void>.broadcast(sync:true);
    final repository=_repo(gateway);
    var revision=1;
    var signedIn=true;
    Widget card()=>MaterialApp(home:Scaffold(body:FablePaymentStatusCard(
      repository:repository,paymentId:firstId,
      identityRevision:()=>revision,
      isAuthenticated:()=>signedIn,
      identityInvalidations:invalidations.stream,
    )));
    await tester.pumpWidget(card());
    expect(gateway.calls,1);
    revision=2;
    invalidations.add(null);
    await tester.pump();
    revision=3; // same A account returns; epoch is NOT reused
    invalidations.add(null);
    await tester.pump();
    gateway.complete(0,firstId,'PAID');
    await tester.pump();
    expect(find.text('PAID'),findsNothing);
    expect(gateway.calls,1); // old payment ID is never auto-refetched
    expect(find.text('Session changed. Reopen payment status to verify.'),
      findsOneWidget);
    signedIn=false;
    await tester.pumpWidget(const SizedBox.shrink());
    await invalidations.close();
  });

  testWidgets('RC316 payment ID changes suppress earlier completed status', (tester)async{
    final gateway=_ControlledGateway();
    final invalidations=StreamController<void>.broadcast(sync:true);
    final repository=_repo(gateway);
    Widget card(String id)=>MaterialApp(home:Scaffold(body:FablePaymentStatusCard(
      repository:repository,paymentId:id,
      identityRevision:()=>10,
      isAuthenticated:()=>true,
      identityInvalidations:invalidations.stream,
    )));
    await tester.pumpWidget(card(firstId));
    expect(gateway.calls,1);
    await tester.pumpWidget(card(secondId));
    expect(gateway.calls,2);
    gateway.complete(0,firstId,'PAID');
    await tester.pump();
    expect(find.text('PAID'),findsNothing);
    gateway.complete(1,secondId,'PENDING');
    await tester.pump();
    expect(find.text('PENDING'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await invalidations.close();
  });

  testWidgets('RC316 logout before a response prevents displaying payment', (tester)async{
    final gateway=_ControlledGateway();
    final invalidations=StreamController<void>.broadcast(sync:true);
    final repository=_repo(gateway);
    var signedIn=true;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FablePaymentStatusCard(
      repository:repository,paymentId:firstId,
      identityRevision:()=>5,
      isAuthenticated:()=>signedIn,
      identityInvalidations:invalidations.stream,
    ))));
    expect(gateway.calls,1);
    signedIn=false; // even if the event arrives late, response must be rejected
    gateway.complete(0,firstId,'SETTLED');
    await tester.pump();
    expect(find.text('SETTLED'),findsNothing);
    expect(find.text('Sign in to view payment status.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await invalidations.close();
  });
  testWidgets('RC345 swapping payment Backend never sends an old ID to the replacement repository', (tester)async{
    final oldGateway=_ControlledGateway(),newGateway=_ControlledGateway();
    final oldRepo=_repo(oldGateway),newRepo=_repo(newGateway);
    final invalidations=StreamController<void>.broadcast(sync:true);
    addTearDown(invalidations.close);
    final revision=()=>8;
    final authenticated=()=>true;
    var repository=oldRepo;
    var paymentId=firstId;
    Widget card()=>MaterialApp(home:Scaffold(body:FablePaymentStatusCard(
      repository:repository,paymentId:paymentId,
      identityRevision:revision,isAuthenticated:authenticated,
      identityInvalidations:invalidations.stream,
    )));
    await tester.pumpWidget(card());
    expect(oldGateway.calls,1);
    repository=newRepo;
    await tester.pumpWidget(card());
    expect(newGateway.calls,0);
    expect(find.textContaining('Session changed'),findsOneWidget);
    oldGateway.complete(0,firstId,'PREVIOUS PRIVATE PAYMENT');
    await tester.pump();
    expect(find.text('PREVIOUS PRIVATE PAYMENT'),findsNothing);
    // Explicitly selecting a different payment ID authorizes a fresh GET.
    paymentId=secondId;
    await tester.pumpWidget(card());
    expect(newGateway.calls,1);
    newGateway.complete(0,secondId,'PENDING');
    await tester.pump();
    expect(find.text('PENDING'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
