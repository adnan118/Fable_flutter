import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

import 'package:fable_messaging/fable_messaging.dart';
class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.ops);
  final Map<String,FableOperation> ops;
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => ops.containsKey(id);
  @override FableOperation require(String id) => ops[id] ?? (throw StateError('unlisted operation'));
}
void main(){
  test('inbound webhooks are rejected as client operations',(){
    final c=FakeCatalog({'webhook':const FableOperation('phone-messages.meta-webhook-receive','POST','/webhooks/whatsapp/meta','h',requiresAuth:false)});
    expect(()=>FableMessageOperations.fromContract(c,'webhook'),throwsFormatException);
  });
  test('verified authenticated client send can be bound',(){
    final c=FakeCatalog({'send':const FableOperation('send','POST','/api/messages/send','h',requiresAuth:true)});
    expect(FableMessageOperations.fromContract(c,'send').sendId,'send');
  });
}
