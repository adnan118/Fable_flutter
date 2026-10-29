import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main(){
  final ops=[{'operationId':'users.me','method':'GET','path':'/users/me','auth':'bearer'}];
  final checksum=sha256.convert(utf8.encode(jsonEncode(ops))).toString();
  final source=List<String>.filled(64, 'a').join();
  final catalog=ExternalOperationCatalog.fromMap({
    'schemaVersion':1,'kind':'fable.external-operation-catalog','adapter':'openapi',
    'baseUrl':'https://api.example.test','sourceHash':source,
    'operations':ops,'operationsHash':checksum,
  });
  Map<String,dynamic> binding()=>{
    'schemaVersion':1,'kind':'fable.feature-operation-bindings','adapter':'openapi',
    'sourceHash':source,'operationsHash':checksum,
    'bindings':{'profile':{'read':'users.me'}},
  };
  test('profile read resolves only an explicit verified operation',(){
    final x=ExternalFeatureBindings.fromMap(binding(),catalog);
    expect(x.operation('profile','read'),'users.me');
    expect(x.operation('payments','create'),isNull);
  });
  test('stale contract hashes fail closed',(){
    final changed=binding()..['operationsHash']=List<String>.filled(64, '0').join();
    expect(()=>ExternalFeatureBindings.fromMap(changed,catalog),throwsFormatException);
  });
  test('bindings must reference real operations',(){
    final changed=binding();
    changed['bindings']={'profile':{'read':'users.unknown'}};
    expect(()=>ExternalFeatureBindings.fromMap(changed,catalog),throwsStateError);
  });
}
