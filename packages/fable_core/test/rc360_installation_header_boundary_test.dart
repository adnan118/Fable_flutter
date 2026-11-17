import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

const _digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _opHash='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _InstallSession extends FableSecureSession {
  _InstallSession(this.value);
  final String value;
  @override Future<String> installationId() async => value;
}
class _OtherCatalog implements OperationCatalog {
  @override bool get sendsInstallationId => false;
  @override bool supports(String operationId) => operationId=='status.public';
  @override FableOperation require(String operationId) {
    if (!supports(operationId)) throw StateError('Unsupported operation');
    return const FableOperation('status.public','GET','/status',_opHash,
      requiresAuth:false,enforceAuth:true);
  }
}
class _InjectInstallationHeader implements BackendTransportAdapter {
  const _InjectInstallationHeader(this.catalog);
  @override final OperationCatalog catalog;
  @override BackendSessionMode get sessionMode => BackendSessionMode.anonymous;
  @override Future<Map<String,String>> headersFor(
    FableOperation operation,FableSecureSession session) async =>
      {'Accept':'application/json',
       'x-installation-ID':'0123456789abcdef0123456789abcdef'};
}
FableContract _fableCatalog()=>const FableContract(
  contractHash:_digest,
  operations:{
    'status.public':FableOperation('status.public','GET','/status',
      _opHash,requiresAuth:false,enforceAuth:true),
  },
  featureIds:{'auth'},
  projectName:'rc360-transport-fixture',
  selectionMode:'explicit',
);
Dio _instrumentedDio(void Function(RequestOptions) hit){
  final dio=Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler){
    hit(request);
    handler.resolve(Response<dynamic>(requestOptions:request,
      statusCode:200,data:{'ok':true}));
  }));
  return dio;
}
void main(){
  test('RC360 reject malformed Fable installation identifiers at adapter boundary',() async {
    final catalog=_fableCatalog();
    final adapter=FableTransportAdapter(catalog:catalog);
    final op=catalog.require('status.public');
    for(final value in [
      '', 'a'*31, 'a'*33, 'A'*32, 'a'*30+'\r\n',
      '../00000000000000000000000000000',
    ]){
      await expectLater(adapter.headersFor(op,_InstallSession(value)),
        throwsFormatException, reason:'installation identifier must be lowercase hex32');
    }
  });
  test('RC360 Fable request sends one source-validated installation identifier',() async{
    var sends=0;
    final api=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:_fableCatalog(),
      session:_InstallSession('0123456789abcdef0123456789abcdef'),
      client:_instrumentedDio((request){
        sends++;
        expect(request.headers['X-Installation-Id'],
          '0123456789abcdef0123456789abcdef');
        expect(request.headers.keys.where((key)=>
          key.toLowerCase()=='x-installation-id'),hasLength(1));
      }),
    );
    addTearDown(api.dispose);
    expect((await api.request('status.public')).statusCode,200);
    expect(sends,1);
  });
  test('RC360 Fable request refuses malformed installation ID before dispatch',() async{
    var sends=0;
    final api=UnifiedApiClient(
      baseUri:Uri.parse('https://api.example.test'),
      contract:_fableCatalog(),
      session:_InstallSession('bad\r\nvalue'),
      client:_instrumentedDio((_)=>sends++),
    );
    addTearDown(api.dispose);
    await expectLater(api.request('status.public'),throwsFormatException);
    expect(sends,0);
  });
  test('RC360 Other Backend injected adapter cannot leak Fable installation ID',() async{
    final catalog=_OtherCatalog();
    var sends=0;
    final api=UnifiedApiClient(
      baseUri:Uri.parse('https://other.example.test'),
      contract:catalog,
      adapter:_InjectInstallationHeader(catalog),
      session:_InstallSession('0123456789abcdef0123456789abcdef'),
      client:_instrumentedDio((_)=>sends++),
    );
    addTearDown(api.dispose);
    await expectLater(api.request('status.public'),throwsStateError);
    expect(sends,0);
  });
}
