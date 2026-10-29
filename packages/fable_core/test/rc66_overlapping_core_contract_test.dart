import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter_test/flutter_test.dart';

String _sha(Object value) => sha256.convert(utf8.encode(jsonEncode(value))).toString();

class _Fixture {
  _Fixture({this.openApiPath='/auth/login', this.corePath='/auth/login',
    this.openApiPublic=true, this.corePublic=true, this.duplicateCore=false});

  final String openApiPath, corePath;
  final bool openApiPublic, corePublic, duplicateCore;

  FableContract parse() {
    const contractHash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const routeHash='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final handoff=<String,dynamic>{
      'schemaVersion':1,
      'kind':'fable.flutter-handoff',
      'client':'flutter',
      'backend':{'project':{'id':'integration-test', 'name':'RC66'},'contractHash':contractHash},
      'selection':{'mode':'explicit','features':['auth']},
    };
    handoff['manifestHash']=_sha(handoff);

    final operations=<Map<String,dynamic>>[
      {'operationId':'auth.login','method':'POST','path':corePath,'public':corePublic},
      {'operationId':'auth.logoutAll','method':'POST','path':'/auth/logout-all','public':false},
    ];
    if(duplicateCore)operations.add(Map<String,dynamic>.from(operations.first));
    final mobileCore=<String,dynamic>{
      'schemaVersion':1,
      'kind':'fable.mobile-core-operations',
      'backendContractHash':contractHash,
      'operations':operations,
      'operationsHash':_sha(operations),
    };
    final openApi=<String,dynamic>{
      'paths':{
        openApiPath:{
          'post':{
            'operationId':'auth.login',
            'x-fable-public':openApiPublic,
            'x-fable-contract-hash':routeHash,
            'security':openApiPublic ? <Object>[] : <Object>[{'bearerAuth':<Object>[]}],
          },
        },
      },
    };
    return FableContract.fromMaps(handoff,
      <String,dynamic>{'contractHash':contractHash},
      openApi,mobileCore:mobileCore);
  }
}

void main() {
  test('RC66 overlap is accepted only with the same HTTP method, path and auth policy', () {
    final catalog=_Fixture().parse();
    expect(catalog.operations.length, 2);
    expect(catalog.require('auth.login').method, 'POST');
    expect(catalog.require('auth.login').path, '/auth/login');
    expect(catalog.require('auth.login').requiresAuth, isFalse);
    expect(catalog.require('auth.login').enforceAuth, isTrue);
    expect(catalog.require('auth.logoutAll').requiresAuth, isTrue);
  });

  test('Conflicting OpenAPI versus mobile-core route fails closed', () {
    expect(() => _Fixture(corePath:'/auth/other').parse(), throwsFormatException);
    expect(() => _Fixture(openApiPath:'/auth/other').parse(), throwsFormatException);
  });

  test('Conflicting public/private authorization fails closed', () {
    expect(() => _Fixture(openApiPublic:false).parse(), throwsFormatException);
    expect(() => _Fixture(corePublic:false).parse(), throwsFormatException);
  });

  test('Duplicates within the mobile-core export still fail closed', () {
    expect(() => _Fixture(duplicateCore:true).parse(), throwsFormatException);
  });
}
