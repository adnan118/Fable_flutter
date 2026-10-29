import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

import 'package:fable_payments/fable_payments.dart';
class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.ops);
  final Map<String,FableOperation> ops;
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => ops.containsKey(id);
  @override FableOperation require(String id) => ops[id] ?? (throw StateError('unlisted operation'));
}
void main(){
  test('payments accept only authenticated individual GET, never checkout as read',(){
    final c=FakeCatalog({'read':const FableOperation('read','GET','/financial/payments/{id}','h'),
     'checkout':const FableOperation('checkout','POST','/financial/payments/{id}/checkout','h')});
    expect(FablePaymentOperations.fromContract(c,'read').readId,'read');
    expect(()=>FablePaymentOperations.fromContract(c,'checkout'),throwsFormatException);
    expect(()=>FablePaymentSnapshot.fromJson({'id':'pay123','status':'PENDING','serverVersion':'v3'}),returnsNormally);
  });
}
