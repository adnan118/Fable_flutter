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
  test('RC226 declared auth without enforced gateway auth is not a client send',(){
    final c=FakeCatalog({
      'weak':const FableOperation('weak','POST','/api/messages/send','h',
        requiresAuth:true,enforceAuth:false),
      'anonymous':const FableOperation('anonymous','POST','/api/messages/send','h',
        requiresAuth:false,enforceAuth:true),
    });
    for(final id in ['weak','anonymous']){
      expect(()=>FableMessageOperations.fromContract(c,id),throwsFormatException);
    }
  });
  test('RC226 mixed-case inbound webhook names and routes are server only',(){
    final c=FakeCatalog({
      'path':const FableOperation('client-send','POST',
        '/api/WEBHOOKS/receive','h',requiresAuth:true,enforceAuth:true),
      'id':const FableOperation('phone.WebHook.Receive','POST',
        '/api/normal-send','h',requiresAuth:true,enforceAuth:true),
      'fragment':const FableOperation('normal','POST',
        '/api/messages/send#hidden','h',requiresAuth:true,enforceAuth:true),
    });
    for(final id in ['path','id','fragment']){
      expect(()=>FableMessageOperations.fromContract(c,id),throwsFormatException);
    }
  });
  test('verified authenticated client send can be bound',(){
    final c=FakeCatalog({'send':const FableOperation('send','POST','/api/messages/send','h',requiresAuth:true,enforceAuth:true)});
    expect(FableMessageOperations.fromContract(c,'send').sendId,'send');
  });
}
