import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _RevisionSession extends FableSecureSession {
  @override int identityRevision = 0;
  void switchUser() => identityRevision++;
}
class _Credentials implements BackendCredentialProvider {
  final recovery=Completer<bool>();
  final recoveryStarted=Completer<void>();
  bool blockRecovery=false;
  @override Future<String?> credentialFor(FableOperation _) async=>'private-key';
  @override Future<bool> recoverUnauthorized(FableOperation _) async{
    recoveryStarted.complete();
    if(blockRecovery)return recovery.future;
    return true;
  }
}
ExternalOperationCatalog _catalog(){
  final operations=<Map<String,String>>[
    {'operationId':'private.read','method':'GET','path':'/account/private',
     'auth':'provider','credentialHeader':'X-Client-Key'},
  ];
  return ExternalOperationCatalog.fromMap({
    'schemaVersion':1,'kind':'fable.external-operation-catalog',
    'adapter':'openapi','baseUrl':'https://api.example.test',
    'sourceHash':'a'*64,
    'operationsHash':sha256.convert(utf8.encode(jsonEncode(operations))).toString(),
    'operations':operations,
  });
}
void main(){
  test('RC343 externally supplied credentials cannot return previous account response after identity switch',() async{
    final session=_RevisionSession(),creds=_Credentials();
    final arrived=Completer<RequestOptions>();
    final resume=Completer<void>();
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
      arrived.complete(request);
      await resume.future;
      handler.resolve(Response<dynamic>(requestOptions:request,statusCode:200,
        data:{'secret':'previous-user'}));
    }));
    final gateway=ExternalApiGateway(catalog:_catalog(),session:session,
      client:dio,credentialProvider:creds);
    addTearDown(gateway.dispose);
    final request=gateway.execute('private.read');
    await arrived.future;
    session.switchUser();
    resume.complete();
    await expectLater(request,throwsA(isA<FableApiException>()
      .having((e)=>e.status,'status',409)));
  });

  test('RC343 external credential recovery cannot retry previous user after switch',() async{
    final session=_RevisionSession(),creds=_Credentials()..blockRecovery=true;
    var sends=0;
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
      sends++;
      handler.resolve(Response<dynamic>(requestOptions:request,statusCode:401));
    }));
    final gateway=ExternalApiGateway(catalog:_catalog(),session:session,
      client:dio,credentialProvider:creds);
    addTearDown(gateway.dispose);
    final request=gateway.execute('private.read');
    await creds.recoveryStarted.future;
    session.switchUser();
    creds.recovery.complete(true);
    await expectLater(request,throwsA(isA<FableApiException>()
      .having((e)=>e.status,'status',409)));
    expect(sends,1);
  });
}
