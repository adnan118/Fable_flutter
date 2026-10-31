import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter_test/flutter_test.dart';

String _hash(Object value)=>sha256.convert(utf8.encode(jsonEncode(value))).toString();

FableContract _importWithPolicy(Map<String,dynamic> policy) {
  const digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const operationHash='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final handoff=<String,dynamic>{
    'schemaVersion':1,'kind':'fable.flutter-handoff','client':'flutter',
    'backend':{'project':{'id':'fable-test','name':'test'},'contractHash':digest},
    'selection':{'mode':'explicit','features':['auth']},
  };
  handoff['manifestHash']=_hash(handoff);
  final contract=<String,dynamic>{
    'contractHash':digest,
    'core':{'auth':{'sessionPolicy':policy}},
  };
  final openApi=<String,dynamic>{
    'paths':{
      '/auth/session-policy':{
        'get':{
          'operationId':'auth.session-policy',
          'x-fable-public':true,
          'x-fable-contract-hash':operationHash,
          'security':<Object>[],
        },
      },
    },
  };
  return FableContract.fromMaps(handoff,contract,openApi);
}

void main() {
  test('Single, bounded multi and unlimited policy are read from backend export',() {
    for(final entry in <(String,int,String,bool)>[
      ('single',1,'revoke-oldest',false),
      ('multi',3,'reject-new',true),
      ('multi',0,'revoke-oldest',true),
      ('multi',1,'reject-new',false),
    ]){
      final contract=_importWithPolicy({
        'mode':entry.$1,'maxActive':entry.$2,'overflow':entry.$3,
        'runtimeEndpoint':'/auth/session-policy','runtimeAuthoritative':true,
      });
      expect(contract.sessionPolicy?.mode,entry.$1);
      expect(contract.sessionPolicy?.maxActive,entry.$2);
      expect(contract.sessionPolicy?.allowsMultipleSessions,entry.$4);
      expect(contract.require('auth.session-policy').requiresAuth,isFalse);
    }
  });

  test('Policy parsing fails closed for malformed backend values',() {
    final good=<String,dynamic>{
      'mode':'multi','maxActive':5,'overflow':'reject-new',
      'runtimeEndpoint':'/auth/session-policy'
    };
    for(final bad in <Map<String,dynamic>>[
      {...good,'mode':'unknown'},
      {...good,'maxActive':-1},
      {...good,'maxActive':101},
      {...good,'maxActive':'5'},
      {...good,'mode':'single','maxActive':5},
      {...good,'overflow':'silently-allow'},
      {...good,'runtimeEndpoint':'/unsafe'},
      {...good,'onePerInstallation':'true'},
    ]){
      expect(()=>_importWithPolicy(bad),throwsFormatException);
    }
  });

  test('Legacy export without explicit policy is unknown, not automatically multi',() {
    final policy=FableSessionPolicy.fromMap({
      'mode':'multi','maxActive':0,'overflow':'revoke-oldest',
      'onePerInstallation':true,
    });
    expect(policy.allowsMultipleSessions,isTrue);
    expect(policy.onePerInstallation,isTrue);
  });
}
