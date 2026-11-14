import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_payments/fable_payments.dart';

const paymentId='550e8400-e29b-41d4-a716-446655440001';
const differentId='550e8400-e29b-41d4-a716-446655440002';

class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.ops);
  final Map<String,FableOperation> ops;
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => ops.containsKey(id);
  @override FableOperation require(String id) =>
    ops[id] ?? (throw StateError('unlisted operation'));
}

class FakePaymentGateway implements BackendApiGateway {
  FakePaymentGateway(this.responseData);
  final Object? responseData;
  int calls=0;
  String? lastOperationId;
  Map<String,dynamic>? lastPath;
  @override Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    calls++;
    lastOperationId=operationId;
    lastPath=path;
    // Tests must never simulate an unsafe payment capture or refund POST.
    expect(body,isNull);
    return Response<dynamic>(
      requestOptions:RequestOptions(path:'/financial/payments'),
      statusCode:200,data:responseData,
    );
  }
  @override void dispose() {}
}

FablePaymentOperations validRead()=>FablePaymentOperations.fromContract(
  FakeCatalog({'read':const FableOperation(
    'read','GET','/financial/payments/{id}','h',
    requiresAuth:true,enforceAuth:true,
  )}),'read');

void main(){
  test('RC223 payment read requires verified enforced auth and an individual GET',(){
    final c=FakeCatalog({
      'read':const FableOperation('read','GET','/financial/payments/{id}','h',
        requiresAuth:true,enforceAuth:true),
      'checkout':const FableOperation('checkout','POST',
        '/financial/payments/{id}/checkout','h',requiresAuth:true,enforceAuth:true),
      'weak':const FableOperation('weak','GET','/financial/payments/{id}','h',
        requiresAuth:true,enforceAuth:false),
      'anonymous':const FableOperation('anonymous','GET',
        '/financial/payments/{id}','h',requiresAuth:false,enforceAuth:true),
      'admin':const FableOperation('admin','GET',
        '/admin/financial/payments/{id}','h',requiresAuth:true,enforceAuth:true),
      'collection':const FableOperation('collection','GET',
        '/financial/payments','h',requiresAuth:true,enforceAuth:true),
      'query':const FableOperation('query','GET',
        '/financial/payments/{id}?include=secret','h',
        requiresAuth:true,enforceAuth:true),
      'credential':const FableOperation('credential','GET',
        '/financial/payments/{id}','h',requiresAuth:true,enforceAuth:true,
        credentialHeader:'X-External-Api-Key'),
    });
    expect(FablePaymentOperations.fromContract(c,'read').readId,'read');
    for(final id in ['checkout','weak','anonymous','admin',
      'collection','query','credential']){
      expect(()=>FablePaymentOperations.fromContract(c,id),throwsFormatException,
        reason:'Unsafe payment operation '+id+' must not become a read');
    }
    expect(()=>FablePaymentSnapshot.fromJson({
      'id':'pay123','status':'PENDING','serverVersion':'v3'}),returnsNormally);
  });

  test('RC223 matching payment ID returned from Backend is accepted once',()async{
    final gateway=FakePaymentGateway({'id':paymentId,'status':'PENDING'});
    final repo=FablePaymentReadRepository(
      gateway:gateway,operations:validRead(),
      decode:FablePaymentSnapshot.fromJson);
    final payment=await repo.read(paymentId);
    expect(payment.id,paymentId);
    expect(payment.status,'PENDING');
    expect(gateway.calls,1);
    expect(gateway.lastOperationId,'read');
    expect(gateway.lastPath,{'id':paymentId});
  });

  test('RC223 mismatched payment data is rejected, never shown under old payment',()async{
    final gateway=FakePaymentGateway({'id':differentId,'status':'PAID'});
    final repo=FablePaymentReadRepository(
      gateway:gateway,operations:validRead(),
      decode:FablePaymentSnapshot.fromJson);
    await expectLater(repo.read(paymentId),throwsFormatException);
    expect(gateway.calls,1);
  });

  test('RC223 equal UUID with different letter case remains same payment',()async{
    const requested='550e8400-e29b-41d4-a716-ABCDEFabcdef';
    final gateway=FakePaymentGateway({
      'id':requested.toLowerCase(),'status':'SETTLED'});
    final repo=FablePaymentReadRepository(
      gateway:gateway,operations:validRead(),
      decode:FablePaymentSnapshot.fromJson);
    final state=await repo.read(requested);
    expect(state.status,'SETTLED');
    expect(gateway.calls,1);
  });

  test('RC223 malformed server response never yields a payment state',()async{
    final gateway=FakePaymentGateway({'id':paymentId,'status':'paid'});
    final repo=FablePaymentReadRepository(
      gateway:gateway,operations:validRead(),
      decode:FablePaymentSnapshot.fromJson);
    await expectLater(repo.read(paymentId),throwsFormatException);
    expect(gateway.calls,1);
  });

  test('RC223 invalid payment ID is rejected before any network operation',()async{
    final gateway=FakePaymentGateway({'id':paymentId,'status':'PENDING'});
    final repo=FablePaymentReadRepository(
      gateway:gateway,operations:validRead(),
      decode:FablePaymentSnapshot.fromJson);
    await expectLater(repo.read('../other-account'),throwsArgumentError);
    expect(gateway.calls,0);
  });
}
