import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

import 'package:fable_support/fable_support.dart';
class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.ops);
  final Map<String,FableOperation> ops;
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => ops.containsKey(id);
  @override FableOperation require(String id) => ops[id] ?? (throw StateError('unlisted operation'));
}
void main(){
  test('support requires authenticated client operations',(){
    final c=FakeCatalog({
      'support.list':const FableOperation('support.list','GET','/support/tickets','hash',requiresAuth:true,enforceAuth:true),
      'support.create':const FableOperation('support.create','POST','/support/tickets','hash',requiresAuth:true,enforceAuth:true)});
    final ops=FableSupportOperations.fromContract(c,listOperationId:'support.list',createOperationId:'support.create');
    expect(ops.createId,'support.create');
    expect(()=>FableSupportTicket.fromJson({'id':'x','status':'open','subject':'test','unknown':'preserved'}),returnsNormally);
    expect(()=>FableSupportTicket.fromJson({'subject':'missing id','status':'open'}),throwsFormatException);
  });
  test('RC144 support never trusts declared auth without gateway enforcement',(){
    final c=FakeCatalog({
      'list':const FableOperation('list','GET','/tickets','hash',requiresAuth:true),
      'create':const FableOperation('create','POST','/tickets','hash',
        requiresAuth:true,enforceAuth:true),
    });
    expect(()=>FableSupportOperations.fromContract(c,
      listOperationId:'list',createOperationId:'create'),throwsFormatException);
  });
  test('RC144 authenticated webhook is still a server-only operation',(){
    final c=FakeCatalog({
      'list':const FableOperation('tickets.webhook.list','GET','/webhooks/tickets',
        'hash',requiresAuth:true,enforceAuth:true),
      'create':const FableOperation('create','POST','/tickets','hash',
        requiresAuth:true,enforceAuth:true),
    });
    expect(()=>FableSupportOperations.fromContract(c,
      listOperationId:'list',createOperationId:'create'),throwsFormatException);
  });
  test('support rejects public and webhook operations',(){
    final c=FakeCatalog({'list':const FableOperation('list','GET','/webhooks/support','h',requiresAuth:false),
      'create':const FableOperation('create','POST','/support','h')});
    expect(()=>FableSupportOperations.fromContract(c,listOperationId:'list',createOperationId:'create'),throwsFormatException);
  });
}
