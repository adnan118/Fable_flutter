import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

class _PublicCatalog implements OperationCatalog {
  const _PublicCatalog();
  @override bool get sendsInstallationId => false;
  @override bool supports(String id) => id == 'status.public';
  @override FableOperation require(String id) {
    if (!supports(id)) throw StateError('Operation unavailable');
    return const FableOperation('status.public','GET','/status',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      requiresAuth:false,enforceAuth:true);
  }
}
Dio _dio(void Function(RequestOptions) onSend) {
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
    onSend(request);
    handler.resolve(Response<dynamic>(requestOptions:request,
      statusCode:200,data:{'ok':true}));
  }));
  return dio;
}
UnifiedApiClient _client(Dio dio)=>UnifiedApiClient(
  baseUri:Uri.parse('https://verified.example.test'),
  contract:const _PublicCatalog(),session:FableSecureSession(),client:dio);

void main(){
  test('RC364 rejects changed Dio origin after credentials are pinned',()async{
    var sends=0;
    final dio=_dio((_) {sends++;});
    final client=_client(dio);
    addTearDown(client.dispose);
    expect(dio.options.baseUrl,'https://verified.example.test');
    dio.options.baseUrl='https://different.example.test';
    await expectLater(client.request('status.public'),throwsStateError);
    expect(sends,0);
  });

  test('RC364 injected Dio cannot add ambient credentials after constructor',()async{
    for(final name in <String>[
      'Authorization','Cookie','X-API-Key','DPoP',
      'x-installation-id','X-Fable-Managed-Entity-Id','X-Fable-Future-Scope',
      'If-Match','Idempotency-Key','X-Security-Challenge-Id',
    ]){
      var sends=0;
      final dio=_dio((_) {sends++;});
      final client=_client(dio);
      try{
        dio.options.headers[name]='forged-value';
        await expectLater(client.request('status.public'),throwsStateError,
          reason:'Must reject mutable Dio default: $name');
        expect(sends,0,reason:name);
      }finally{client.dispose();}
    }
  });

  test('RC364 transport still accepts benign public locale headers',()async{
    var sends=0;
    final dio=_dio((request){
      sends++;
      expect(request.headers['Accept-Language'],'ar');
    });
    final client=_client(dio);
    addTearDown(client.dispose);
    dio.options.headers['Accept-Language']='ar';
    expect((await client.request('status.public')).statusCode,200);
    expect(sends,1);
  });

  test('RC364 rejects spoofed device header already present at construction',(){
    final dio=Dio(BaseOptions(headers:{
      'X-Installation-Id':'0123456789abcdef0123456789abcdef',
    }));
    expect(()=>_client(dio),throwsArgumentError);
    dio.close(force:true);
  });
}
