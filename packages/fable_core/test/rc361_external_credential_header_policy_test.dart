import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const _hash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ExternalOperationCatalog _import(String credentialHeader) {
  final ops=<Map<String,String>>[
    {'operationId':'private.read','method':'GET','path':'/private',
     'auth':'provider','credentialHeader':credentialHeader},
  ];
  return ExternalOperationCatalog.fromMap({
    'schemaVersion':1,'kind':'fable.external-operation-catalog',
    'adapter':'openapi','baseUrl':'https://external.example.test',
    'sourceHash':_hash,'operationsHash':sha256.convert(
       utf8.encode(jsonEncode(ops))).toString(),'operations':ops,
  });
}
class _ForgedCatalog implements OperationCatalog {
  const _ForgedCatalog(this.header);
  final String header;
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>id=='private.read';
  @override FableOperation require(String id)=>FableOperation(
     'private.read','GET','/private',_hash,requiresAuth:true,
     enforceAuth:true,credentialHeader:header);
}
class _Credentials implements BackendCredentialProvider {
  int calls=0;
  @override Future<String?> credentialFor(FableOperation operation) async {
    calls++;
    return 'private-value';
  }
  @override Future<bool> recoverUnauthorized(FableOperation operation)async=>false;
}

void main(){
  test('RC361 external importer rejects transport and security-proof headers',(){
    for(final header in <String>[
      'DPoP','dpop','If-Match','Idempotency-Key','Range',
      'X-Installation-Id','X-Fable-Managed-Entity-Id',
      'X-Fable-Managed-Account-Id','X-Fable-Media-Token',
      'X-Security-Challenge-Id','X-CSRF-Token',
      'Content-Type','Accept','X-Fable-Future-Proof',
    ]){
      expect(()=>_import(header),throwsFormatException,reason:header);
    }
  });

  test('RC361 declared Basic and API-key credentials remain supported',(){
    for(final header in ['Authorization','X-API-Key','X-Client-Key']){
      final catalog=_import(header);
      expect(catalog.require('private.read').credentialHeader,header);
    }
  });

  test('RC361 forged external operation cannot dispatch reserved credential header',()async{
    for(final header in ['DPoP','X-Fable-Media-Token','If-Match']){
      final catalog=_ForgedCatalog(header);
      final credentials=_Credentials();
      var sends=0;
      final dio=Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
        sends++;
        handler.resolve(Response<dynamic>(requestOptions:request,
          statusCode:200,data:<String,dynamic>{}));
      }));
      final client=UnifiedApiClient(
        baseUri:Uri.parse('https://external.example.test'),
        contract:catalog,session:FableSecureSession(),
        credentialProvider:credentials,client:dio);
      try{
        await expectLater(client.request('private.read'),throwsStateError);
        expect(sends,0);
        expect(credentials.calls,0);
      }finally{client.dispose();}
    }
  });

  test('RC361 synthetic Fable contract cannot enable custom credential headers',()async{
    final catalog=FableContract(
      contractHash:_hash,
      operations:{
        'private.read':const FableOperation('private.read','GET','/private',
           _hash,requiresAuth:true,enforceAuth:true,
           credentialHeader:'X-API-Key'),
      },
      featureIds:const {'auth'},projectName:'rc361-source-only',
      selectionMode:'explicit',
    );
    final client=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:catalog,session:FableSecureSession());
    try{
      await expectLater(client.request('private.read'),throwsStateError);
    }finally{client.dispose();}
  });
}
