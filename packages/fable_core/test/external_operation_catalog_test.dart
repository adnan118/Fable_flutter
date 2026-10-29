import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

Map<String,dynamic> catalog({String auth='bearer'}) {
  final operations=<Map<String,dynamic>>[
    {'operationId':'items.read','method':'GET','path':'/v1/items/{id}','auth':auth},
  ];
  final checksum=sha256.convert(utf8.encode(jsonEncode(operations))).toString();
  return {
    'schemaVersion':1,'kind':'fable.external-operation-catalog',
    'adapter':'openapi','baseUrl':'https://api.example.test',
    'sourceHash':List<String>.filled(64, 'a').join(), 'operations':operations,'operationsHash':checksum,
  };
}
void main(){
  test('external contract reads declared operations only',(){
    final contract=ExternalOperationCatalog.fromMap(catalog());
    expect(contract.supports('items.read'),isTrue);
    expect(contract.require('items.read').requiresAuth,isTrue);
    expect(contract.require('items.read').enforceAuth,isTrue);
    expect(contract.sendsInstallationId,isFalse);
    expect(()=>contract.require('auth.login'),throwsStateError);
  });
  test('tampered operations cannot be loaded',(){
    final modified=catalog();
    (modified['operations'] as List).first['path']='/admin';
    expect(()=>ExternalOperationCatalog.fromMap(modified),throwsFormatException);
  });
  test('external catalog cannot route over arbitrary unencrypted backend',(){
    final modified=catalog();modified['baseUrl']='http://insecure.example.com';
    expect(()=>ExternalOperationCatalog.fromMap(modified),throwsFormatException);
  });
  test('external catalog rejects duplicate operation names',(){
    final modified=catalog();
    final operations=modified['operations'] as List;
    operations.add(Map<String,dynamic>.of(operations.first as Map<String,dynamic>));
    modified['operationsHash']=sha256.convert(utf8.encode(jsonEncode(operations))).toString();
    expect(()=>ExternalOperationCatalog.fromMap(modified),throwsFormatException);
  });
}
