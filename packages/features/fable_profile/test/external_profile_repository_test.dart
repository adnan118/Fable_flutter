import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_profile/src/external_profile_repository.dart';

void main() {
  final operations = <Map<String, dynamic>>[
    {'operationId':'users.me','method':'GET','path':'/users/me','auth':'bearer'},
  ];
  final hash = sha256.convert(utf8.encode(jsonEncode(operations))).toString();
  final source = List.filled(64, 'a').join();
  final catalog = ExternalOperationCatalog.fromMap({
    'schemaVersion':1,'kind':'fable.external-operation-catalog','adapter':'openapi',
    'baseUrl':'https://api.example.com','sourceHash':source,'operations':operations,'operationsHash':hash,
  });
  final bindings = ExternalFeatureBindings.fromMap({
    'schemaVersion':1,'kind':'fable.feature-operation-bindings','adapter':'openapi',
    'sourceHash':source,'operationsHash':hash,'bindings':{'profile':{'read':'users.me'}},
  },catalog);
  final fields = <String,dynamic>{'schemaVersion':1,'kind':'fable.external-profile-fields',
    'adapter':'openapi','sourceHash':source,'operationsHash':hash,'readOperationId':'users.me',
    'fields':{'displayName':'data.user.name','email':'data.user.email'}};
  test('project custom backend profile using explicit selectors', () {
    final profile = ExternalProfileFields.fromMap(fields,catalog,bindings);
    final result = profile.project({'data':{'user':{'name':'  Maya  ','email':'maya@example.com'}}});
    expect(result.displayName,'Maya');expect(result.email,'maya@example.com');
    expect(result.raw['data']['user']['name'],'  Maya  ');
    final extended = profile.project({'data':{'user':{'name':'Maya'}},'extensions':{'status':'verified','flags':[1,2]}});
    expect(extended.raw['extensions']['flags'],[1,2]);
    expect(() => extended.raw['extensions']['flags'].add(3), throwsUnsupportedError);
    expect(() => extended.raw['extensions']['status']='changed', throwsUnsupportedError);
  });
  test('reject stale mapping and unsafe selectors', () {
    expect(() => ExternalProfileFields.fromMap({...fields,'operationsHash':List.filled(64, 'b').join()},catalog,bindings),throwsFormatException);
    expect(() => ExternalProfileFields.fromMap({...fields,'fields':{'displayName':'data.__proto__.name'}},catalog,bindings),throwsFormatException);
  });
  test('RC224 personal profile refuses anonymous or provider-wide credential GET',(){
    for(final auth in ['none','provider']){
      final op=<String,dynamic>{
        'operationId':'users.me','method':'GET',
        'path':'/users/me','auth':auth,
        if(auth=='provider')'credentialHeader':'X-Provider-Key',
      };
      final operations=<Map<String,dynamic>>[op];
      final operationsHash=sha256.convert(
        utf8.encode(jsonEncode(operations))).toString();
      final c=ExternalOperationCatalog.fromMap({
        'schemaVersion':1,
        'kind':'fable.external-operation-catalog',
        'adapter':'openapi','baseUrl':'https://api.example.com',
        'sourceHash':source,'operationsHash':operationsHash,
        'operations':operations,
      });
      final b=ExternalFeatureBindings.fromMap({
        'schemaVersion':1,'kind':'fable.feature-operation-bindings',
        'adapter':'openapi','sourceHash':source,
        'operationsHash':operationsHash,
        'bindings':{'profile':{'read':'users.me'}},
      },c);
      expect(()=>ExternalProfileFields.fromMap({
        ...fields,'operationsHash':operationsHash,
      },c,b),throwsFormatException,
      reason:'Personal profile must not use shared ${auth} credentials');
    }
  });

  test('RC224 verified Bearer profile GET stays supported',(){
    final user=ExternalProfileFields.fromMap(fields,catalog,bindings);
    expect(user.operationId,'users.me');
    expect(user.project({'data':{'user':{
      'name':'Private User','email':'user@example.com',
    }}}).displayName,'Private User');
  });

  test('fail closed on incomplete payload', () {
    final profile=ExternalProfileFields.fromMap(fields,catalog,bindings);
    expect(() => profile.project({'data':{'user':{'email':'test@example.com'}}}),throwsFormatException);
  });
}
