import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _Catalog implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id == 'api.get';
  @override FableOperation require(String id) => FableOperation(id,'GET','/api/me','hash',
    requiresAuth:true,enforceAuth:true);
}

void main() {
  test('External API headers do not include any Fable-specific headers',() async {
    final catalog=_Catalog();
    final headers=await ExternalTransportAdapter(catalog:catalog,
      publicHeaders:const {'Accept-Language':'ar'}).headersFor(
      catalog.require('api.get'),FableSecureSession());
    expect(headers['Accept'],'application/json');
    expect(headers['Accept-Language'],'ar');
    expect(headers.containsKey('X-Installation-Id'),false);
    expect(headers.containsKey('Authorization'),false);
  });
  test('Never allow auth or spoofed transport headers from custom adapter', () {
    final catalog=_Catalog();
    for(final key in <String>['Authorization','X-API-Key','Cookie','X-Installation-Id']) {
      expect(()=>ExternalTransportAdapter(catalog:catalog,publicHeaders:{key:'secret'}),throwsArgumentError);
    }
  });
  test('Fable public route is public; protected route enforces Bearer',() {
    const digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final handoff=<String,dynamic>{'kind':'fable.flutter-handoff','client':'flutter',
      'schemaVersion':1,'backend':{'contractHash':digest,'project':{'name':'reference'}},
      'selection':{'mode':'advisory','features':null}};
    handoff['manifestHash']=sha256.convert(utf8.encode(jsonEncode(handoff))).toString();
    final openapi={'paths':{
      '/status':{'get':{'operationId':'status.read','x-fable-public':true,'x-fable-contract-hash':'ok',
        'security':<Object>[]}},
      '/accounts':{'get':{'operationId':'accounts.list','x-fable-public':false,'x-fable-contract-hash':'ok',
        'security':[{'bearerAuth':<Object>[]}]}}
    }};
    final parsed=FableContract.fromMaps(handoff,{'contractHash':digest},openapi);
    expect(parsed.require('status.read').requiresAuth,false);
    expect(parsed.require('accounts.list').requiresAuth,true);
    expect(parsed.require('status.read').enforceAuth,true);
  });
}
