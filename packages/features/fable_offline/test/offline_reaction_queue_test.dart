import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_offline/src/offline_reaction_queue.dart';

class Catalog implements OperationCatalog {
  Catalog(this.operation);
  final FableOperation operation;
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>id==operation.id;
  @override FableOperation require(String id){
    if(!supports(id))throw ArgumentError('missing');
    return operation;
  }
}
void main(){
  test('payment-like operation cannot be granted offline replay',(){
    const op=FableOperation('payment.create','POST','/payments','hash',requiresAuth:true);
    expect(()=>OfflineReactionQueue(backendOrigin:Uri.parse('https://api.example.com'),
      accountId:'user',catalog:Catalog(op),serverApprovedOperations:{op.id}),throwsArgumentError);
  });
  test('requires authenticated write and trusted origin',(){
    const op=FableOperation('social.react','POST','/react','hash',requiresAuth:true);
    expect(()=>OfflineReactionQueue(backendOrigin:Uri.parse('http://remote.example.com'),
      accountId:'user',catalog:Catalog(op),serverApprovedOperations:{op.id}),throwsArgumentError);
    const readonly=Catalog(const FableOperation('social.react','GET','/react','hash',requiresAuth:false));
    expect(()=>OfflineReactionQueue(backendOrigin:Uri.parse('https://api.example.com'),
      accountId:'user',catalog:readonly,serverApprovedOperations:{op.id}),throwsArgumentError);
  });
}
