import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_realtime/src/public_change_sync.dart';

class FakeCatalog implements OperationCatalog {
  FakeCatalog(this.operation);
  final FableOperation operation;
  @override bool get sendsInstallationId=>false;
  @override bool supports(String id)=>id==operation.id;
  @override FableOperation require(String id){
    if(!supports(id))throw ArgumentError('Missing operation');
    return operation;
  }
}
class FakeGateway implements BackendApiGateway {
  @override Future<Response<dynamic>> execute(String op,{Map<String,dynamic>? path,
    Map<String,dynamic>? query,Object? body,CancelToken? cancelToken,String? ifMatch}) async =>
    Response(requestOptions:RequestOptions(path:'/'),data:{'revision':'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','unchanged':false,'entries':[]});
  @override void dispose(){}
}
void main(){
  test('reject protected endpoint and mutation to prevent sending public SSE credentials',(){
    final gateway=FakeGateway();
    for(final operation in [
      const FableOperation('changes','POST','/changes','sha',requiresAuth:false),
      const FableOperation('changes','GET','/changes','sha',requiresAuth:true),
    ]){
      expect(()=>PublicChangeSync(gateway:gateway,catalog:FakeCatalog(operation),
        operationId:'changes',namespace:'https://api.example.com'),throwsArgumentError);
    }
  });
  test('reject unsafe origins and too-fast polling',(){
    const public=FableOperation('changes','GET','/changes','sha',requiresAuth:false);
    final catalog=FakeCatalog(public);
    expect(()=>PublicChangeSync(gateway:FakeGateway(),catalog:catalog,operationId:'changes',
      namespace:'http://api.example.com'),throwsArgumentError);
    expect(()=>PublicChangeSync(gateway:FakeGateway(),catalog:catalog,operationId:'changes',
      namespace:'https://api.example.com',checkInterval:const Duration(seconds:1)),throwsArgumentError);
  });
}
