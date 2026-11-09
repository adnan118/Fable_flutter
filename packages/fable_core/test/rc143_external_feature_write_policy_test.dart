import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

ExternalOperationCatalog catalogFor(List<Map<String,Object?>> operations){
  final hash=sha256.convert(utf8.encode(jsonEncode(operations))).toString();
  return ExternalOperationCatalog.fromMap({
    'schemaVersion':1,'kind':'fable.external-operation-catalog',
    'adapter':'openapi','baseUrl':'https://api.example.test',
    'sourceHash':List<String>.filled(64,'a').join(),'operationsHash':hash,'operations':operations,
  });
}
ExternalFeatureBindings bindingsFor(ExternalOperationCatalog catalog,
    String feature,String action,String operationId) =>
  ExternalFeatureBindings.fromMap({
    'schemaVersion':1,'kind':'fable.feature-operation-bindings',
    'adapter':'openapi','sourceHash':catalog.sourceHash,
    'operationsHash':catalog.operationsHash,
    'bindings':{feature:{action:operationId}},
  },catalog);

void main(){
  test('RC143 authenticated Support create remains allowed with verified contract',(){
    final catalog=catalogFor([{
      'operationId':'support.create','method':'POST',
      'path':'/tickets','auth':'bearer',
    }]);
    final binding=bindingsFor(catalog,'support','create','support.create');
    expect(binding.operation('support','create'),'support.create');
  });
  test('RC143 public POST cannot masquerade as authorized client create',(){
    final catalog=catalogFor([{
      'operationId':'public.submit','method':'POST',
      'path':'/support/messages','auth':'none',
    }]);
    expect(()=>bindingsFor(catalog,'support','create','public.submit'),
      throwsFormatException);
  });
  test('RC143 provider credential operations never enter consumer screens',(){
    final catalog=catalogFor([{
      'operationId':'messages.provider','method':'POST',
      'path':'/api/messages/send','auth':'provider',
      'credentialHeader':'X-Provider-Key',
    }]);
    expect(()=>bindingsFor(catalog,'messaging','create','messages.provider'),
      throwsFormatException);
  });
  test('RC143 inbound webhooks cannot become a phone message sender',(){
    final catalog=catalogFor([{
      'operationId':'messages.webhook','method':'POST',
      'path':'/webhooks/meta','auth':'bearer',
    }]);
    expect(()=>bindingsFor(catalog,'messaging','create','messages.webhook'),
      throwsFormatException);
  });
  test('RC143 financial mutation needs dedicated verified financial adapter',(){
    final catalog=catalogFor([{
      'operationId':'payments.checkout','method':'POST',
      'path':'/financial/checkout','auth':'bearer',
    }]);
    expect(()=>bindingsFor(catalog,'payments','create','payments.checkout'),
      throwsFormatException);
  });
  test('RC143 read-only payment state remains bindable',(){
    final catalog=catalogFor([{
      'operationId':'payments.read','method':'GET',
      'path':'/financial/payments/{id}','auth':'bearer',
    }]);
    expect(bindingsFor(catalog,'payments','read','payments.read')
      .operation('payments','read'),'payments.read');
  });
  test('RC143 malformed feature identifiers cannot sneak through bindings',(){
    final catalog=catalogFor([{
      'operationId':'tickets.list','method':'GET',
      'path':'/tickets','auth':'bearer',
    }]);
    expect(()=>bindingsFor(catalog,'../tickets','list','tickets.list'),
      throwsFormatException);
  });
}
