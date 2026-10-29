import 'package:dio/dio.dart';
import 'fable_api.dart';
import 'fable_session.dart';
import 'backend_transport_adapter.dart';
import 'external_operation_catalog.dart';
import 'external_feature_bindings.dart';
import 'backend_credential_provider.dart';

/// An actual contract-bound external backend HTTP client.
/// No hardcoded login, payments, retry or logout endpoint is assumed.
/// Consumers must explicitly map their backend's domain operations to catalog IDs.
class ExternalApiGateway implements BackendApiGateway {
  ExternalApiGateway({required this.catalog,required FableSecureSession session,
    Dio? client, bool allowHttpForLocalDevelopment=false, RefreshSession? refreshSession,
    BackendSessionMode sessionMode=BackendSessionMode.singleBearer,
    Map<String,String>? publicHeaders, BackendCredentialProvider? credentialProvider}) :
    _api=UnifiedApiClient(baseUri:catalog.baseUri,contract:catalog,session:session,
      client:client,refreshSession:refreshSession,credentialProvider:credentialProvider,
      adapter:ExternalTransportAdapter(catalog:catalog,sessionMode:sessionMode,publicHeaders:publicHeaders ?? catalog.publicHeaders),
      allowHttpForLocalDevelopment:allowHttpForLocalDevelopment);
  final ExternalOperationCatalog catalog;
  final UnifiedApiClient _api;

  @override
  Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  }) => _api.request(operationId,path:path,query:query,body:body,cancelToken:cancelToken,ifMatch:ifMatch);
  /// Invoke a consciously bound feature role; the route and HTTP verb must
  /// originate from the verified API catalog. No guessed endpoints or auth.
  Future<Response<dynamic>> executeFeature({
    required ExternalFeatureBindings bindings,
    required String feature,
    required String role,
    Map<String,dynamic>? path,
    Map<String,dynamic>? query,
    Object? body,
    CancelToken? cancelToken,
  }) {
    final operationId=bindings.operation(feature,role);
    if(operationId==null)throw StateError('Feature role is not bound: $feature.$role');
    return execute(operationId,path:path,query:query,body:body,cancelToken:cancelToken);
  }
  @override
  void dispose()=>_api.dispose();
}
