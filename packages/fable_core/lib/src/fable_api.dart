import 'dart:async';
import 'package:dio/dio.dart';
import 'fable_contract.dart';
import 'fable_session.dart';
import 'backend_transport_adapter.dart';
import 'backend_credential_provider.dart';
import 'fable_retry_policy.dart';

/// The refresh callback must use the backend's published auth contract.
/// It is intentionally NOT implemented by guessing /auth/refresh.
typedef RefreshSession = Future<bool> Function();
/// Uniform HTTP transport for all selected backend contracts.
/// Fable-specific requirements live only in FableTransportAdapter.
abstract interface class BackendApiGateway {
  Future<Response<dynamic>> execute(String operationId,{Map<String,dynamic>? path,
    Map<String,dynamic>? query,Object? body,CancelToken? cancelToken,String? ifMatch});
  void dispose();
}

class UnifiedApiClient implements BackendApiGateway {
  UnifiedApiClient({required Uri baseUri,required this.contract,required this.session,
    this.refreshSession, this.credentialProvider, BackendTransportAdapter? adapter,
    bool allowHttpForLocalDevelopment=false, Dio? client,
    this.retryPolicy=const FableRetryPolicy()}) :
    _baseUri=baseUri,
    adapter=adapter ?? (contract.sendsInstallationId
      ? FableTransportAdapter(catalog:contract)
      : ExternalTransportAdapter(catalog:contract,sessionMode:refreshSession==null
        ? BackendSessionMode.singleBearer:BackendSessionMode.rotatingBearer)),
    _dio=client ?? Dio(BaseOptions(baseUrl:baseUri.toString(),
      connectTimeout:const Duration(seconds:8),receiveTimeout:const Duration(seconds:18),sendTimeout:const Duration(seconds:12),
      followRedirects:false,validateStatus:(status)=> status!=null && status<500)) {
    retryPolicy.validate();
    if (baseUri.scheme!='https' && !(allowHttpForLocalDevelopment && baseUri.scheme=='http' &&
      const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(baseUri.host))) {
      throw ArgumentError('HTTPS required for remote backend');
    }
    if (!baseUri.hasAuthority || baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty || baseUri.hasQuery || baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw ArgumentError('Backend base URL must be a bare origin');
    }
    // An injected Dio is a trusted transport dependency, but MUST NOT carry
    // ambient credentials in BaseOptions. Such defaults could leak to public
    // operations even when our own request headers contain no token.
    const ambientCredentials = <String>{
      'authorization', 'cookie', 'proxy-authorization', 'x-api-key',
    };
    if (_dio.options.headers.keys.any((key) =>
        ambientCredentials.contains(key.toString().toLowerCase()))) {
      throw ArgumentError('Do not put authentication credentials in Dio BaseOptions');
    }
    if (!identical(this.adapter.catalog, contract)) {
      throw ArgumentError('Backend adapter must use the verified catalog');
    }
  }
  final Uri _baseUri;
  final OperationCatalog contract;
  final BackendTransportAdapter adapter;
  final FableSecureSession session;
  final Dio _dio;
  final FableRetryPolicy retryPolicy;
  // Use the validated origin for every request even when a Dio is injected.
  // A feature must never substitute a host via an operation path.
  final RefreshSession? refreshSession;
  /// Inject a scheme-specific, runtime-only provider for declared non-Bearer
  /// protected operations. Transport and features never inspect its secrets.
  final BackendCredentialProvider? credentialProvider;
  Future<bool>? _refreshing;
  int? _refreshingIdentity;
  Future<Response<dynamic>> request(String operationId,{Map<String,dynamic>? path,
    Map<String,dynamic>? query,Object? body,bool? authorized,CancelToken? cancelToken,String? ifMatch}) async {
    final op=contract.require(operationId);
    // A quote revision must come from an immediately preceding authoritative
    // server GET; never let shared cache/ARB supply a payment precondition.
    if (ifMatch != null && (!RegExp(r'^[a-f0-9]{64}$').hasMatch(ifMatch) ||
        const <String>{'GET','HEAD'}.contains(op.method.toUpperCase()) ||
        !op.requiresAuth)) {
      throw ArgumentError('If-Match requires a verified authenticated mutation and SHA-256 revision');
    }

    final requestIdentity = session.identityRevision;
    final useAuthorization=authorized ?? op.requiresAuth;
    // The imported backend contract is authoritative about token exposure.
    // Never let callers attach a bearer token to a declared public route,
    // or suppress authorization on a protected external backend route.
    if (op.enforceAuth && useAuthorization != op.requiresAuth) {
      throw ArgumentError('Authorization override conflicts with backend contract: $operationId');
    }
    if(!op.path.startsWith('/') || op.path.startsWith('//') ||
      op.path.contains('..') || op.path.contains('\\') ||
      op.path.contains('?') || op.path.contains('#') || op.path.contains('%')){
      throw const FormatException('Backend contract operation has unsafe path');
    }
    var endpoint=op.path;
    for(final placeholder in RegExp(r'\{([a-zA-Z_][a-zA-Z_0-9]*)\}').allMatches(endpoint)){
      final name=placeholder.group(1)!;
      final value=path?[name];
      if(value==null)throw ArgumentError('Missing path parameter: $name');
      final text=value.toString();
      if(text=='.'||text=='..'||text.contains('\\')||text.contains('/')||text.contains('?')||text.contains('#')||text.contains('%')) {
        throw ArgumentError('Unsafe path parameter: $name');
      }
      endpoint=endpoint.replaceAll('{$name}',Uri.encodeComponent(text));
    }
    if (RegExp(r'\{[^}]*\}').hasMatch(endpoint)) {
      throw const FormatException('Unresolved backend path parameter');
    }
    final headers=await adapter.headersFor(op,session);
    if (ifMatch != null) headers['If-Match']='"$ifMatch"';
    // Authentication is controlled by the verified operation contract,
    // never by an untrusted header map or a feature-level guess.
    if (headers.keys.any((key) => const <String>{
      'authorization','cookie','set-cookie','host','proxy-authorization',
      'forwarded','x-forwarded-for','x-forwarded-host','connection',
      'origin','referer','content-length','transfer-encoding','content-type',
    }.contains(key.toLowerCase()))) {
      throw StateError('Backend adapter attempted to inject a transport-owned header');
    }
    String? accessTokenSent;
    if (useAuthorization && op.credentialHeader == null &&
        adapter.sessionMode == BackendSessionMode.anonymous) {
      throw FableApiException(401, 'unsupported_auth_strategy');
    }
    if (useAuthorization && op.credentialHeader != null) {
      final provider=credentialProvider;
      if (provider == null) throw FableApiException(401,'credential_provider_required');
      final credential=await provider.credentialFor(op);
      if (credential == null || credential.isEmpty) throw FableApiException(401,'auth_required');
      _validateCredentialValue(credential);
      // Never allow a public header or a transport adapter to control auth.
      if (headers.keys.any((h)=>h.toLowerCase()==op.credentialHeader!.toLowerCase())) {
        throw StateError('Credential header overlaps with transport headers');
      }
      headers[op.credentialHeader!] = credential;
    } else if(useAuthorization){
      final token=await session.accessToken;
      if(token==null || token.isEmpty){
        throw FableApiException(401,'auth_required');
      }
      _validateCredentialValue(token);
      accessTokenSent = token;
      headers['Authorization']='Bearer $token';
    }
    if (useAuthorization && op.credentialHeader == null &&
        session.identityRevision != requestIdentity) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    final response=await _send(op,endpoint,headers,query,body,cancelToken,
      expectedIdentity: useAuthorization ? requestIdentity : null);
    // Discard in-flight responses for a previous account, including successes.
    if (useAuthorization && op.credentialHeader == null &&
        session.identityRevision != requestIdentity) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    if (response.statusCode != 401 || !useAuthorization) return _checked(response);
    // A cancellation must not trigger credential recovery or replay.
    if (cancelToken?.isCancelled ?? false) {
      throw FableApiException(0, 'request_cancelled');
    }
    if (op.credentialHeader != null) {
      final provider=credentialProvider!;
      final recovered=await provider.recoverUnauthorized(op);
      if (!recovered) return _checked(response);
      if (!const {'GET','HEAD'}.contains(op.method)) {
        throw FableApiException(401,'session_refreshed_retry_manually');
      }
      final credential=await provider.credentialFor(op);
      if (credential==null || credential.isEmpty) throw FableApiException(401,'auth_required');
      _validateCredentialValue(credential);
      headers[op.credentialHeader!] = credential;
      if (cancelToken?.isCancelled ?? false) {
        throw FableApiException(0, 'request_cancelled');
      }
      return _checked(await _send(op,endpoint,headers,query,body,cancelToken,
        expectedIdentity: requestIdentity));
    }

    if (adapter.sessionMode != BackendSessionMode.rotatingBearer || refreshSession == null) {
      if (adapter.sessionMode == BackendSessionMode.singleBearer) {
        // This backend declared a single expiring/revocable Bearer credential,
        // so there is no refresh operation to invent or call.
        // A definitive 401 requires a new login; 403 retains the session.
        // Another concurrent login or token rotation must not be invalidated
        // by the 401 response of a request carrying an older credential.
        if (await session.accessToken == accessTokenSent) {
          await session.clearSessionIfIdentity(requestIdentity, expectedAccessToken: accessTokenSent);
        }
      }
      return _checked(response);
    }
    if (session.identityRevision != requestIdentity) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    // Requests can receive 401 out of order. If another request has already
    // rotated the access token, reuse that session instead of rotating its
    // refresh token AGAIN. This is important with one-time refresh tokens.
    var fresh = await session.accessToken;
    if (fresh == null || fresh == accessTokenSent) {
      // Never reuse a refresh started for a DIFFERENT logged-in identity.
      // Old refresh responses may complete after a new account logs in.
      final inFlight = _refreshing != null && _refreshingIdentity == requestIdentity
          ? _refreshing! : refreshSession!();
      _refreshing = inFlight;
      _refreshingIdentity = requestIdentity;
      bool success = false;
      try {
        success = await inFlight;
      } finally {
        if (identical(_refreshing, inFlight)) {
          _refreshing = null;
          _refreshingIdentity = null;
        }
      }
      if (!success) {
        if (session.identityRevision != requestIdentity) {
          // A rejected refresh may have cleared the expired session itself.
          // Distinguish that from a newer login that must be preserved.
          if (await session.accessToken == null) {
            throw FableApiException(401, 'session_expired');
          }
          throw FableApiException(409, 'session_changed_discard_response');
        }
        if (await session.accessToken == accessTokenSent) {
          await session.clearSessionIfIdentity(requestIdentity, expectedAccessToken: accessTokenSent);
        }
        throw FableApiException(401, 'session_expired');
      }
      fresh = await session.accessToken;
    }
    if (session.identityRevision != requestIdentity) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    if (fresh == null || fresh.isEmpty) {
      throw FableApiException(401, 'session_expired');
    }
    _validateCredentialValue(fresh);
    if (!const {'GET','HEAD'}.contains(op.method)) {
      // A server or proxy may have processed a mutation even if its response is 401.
      // Never automatically repeat a payment, logout or profile update on refresh.
      throw FableApiException(401,'session_refreshed_retry_manually');
    }
    if (cancelToken?.isCancelled ?? false) {
      throw FableApiException(0, 'request_cancelled');
    }
    headers['Authorization']='Bearer $fresh';
    final retried=await _send(op,endpoint,headers,query,body,cancelToken,
      expectedIdentity: requestIdentity);
    if (session.identityRevision != requestIdentity) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    if (retried.statusCode == 401 && await session.accessToken == fresh) {
      await session.clearSessionIfIdentity(requestIdentity, expectedAccessToken: fresh);
    }
    return _checked(retried);
  }
  static void _validateCredentialValue(String value) {
    if (value.length > 8192 || value.contains(RegExp(r'[\r\n\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid credential header value');
    }
  }
  String _origin() => _baseUri.origin;
  Future<Response<dynamic>> _send(FableOperation op,String endpoint,Map<String,String> headers,
      Map<String,dynamic>? query,Object? body,CancelToken? cancelToken,
      {int? expectedIdentity}) async {
    final safeRead = retryPolicy.canRetryMethod(op.method);
    for (var attempt = 0;; attempt++) {
      if (expectedIdentity != null && session.identityRevision != expectedIdentity) {
        throw FableApiException(409, 'session_changed_discard_response');
      }
      if (cancelToken?.isCancelled ?? false) {
        throw FableApiException(0, 'request_cancelled');
      }
      try {
        final response = await _dio.request<dynamic>(
          Uri.parse('${_origin()}$endpoint').toString(),
          options: Options(method: op.method, headers: headers,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500),
          queryParameters: query, data: body, cancelToken: cancelToken,
        );
        if (safeRead && attempt < retryPolicy.maxReadRetries &&
            retryPolicy.retryableStatus(response.statusCode ?? 0)) {
          final delay = retryPolicy.backoff(attempt,
            retryAfter: response.headers.value('retry-after'));
          if (delay != null) {
            await Future<void>.delayed(delay);
            continue;
          }
        }
        return response;
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        if (safeRead && attempt < retryPolicy.maxReadRetries &&
            (retryPolicy.retryableTransport(error) ||
             retryPolicy.retryableStatus(status))) {
          final delay = retryPolicy.backoff(attempt,
            retryAfter: error.response?.headers.value('retry-after'));
          if (delay != null) {
            await Future<void>.delayed(delay);
            continue;
          }
        }
        if (cancelToken?.isCancelled ?? false ||
            error.type == DioExceptionType.cancel) {
          throw FableApiException(0, 'request_cancelled');
        }
        final payload = error.response?.data;
        final code = payload is Map
            ? (payload['errorCode'] ?? payload['code'] ?? 'network_error').toString()
            : 'network_error';
        throw FableApiException(status, code, details: payload);
      }
    }
  }
  Response<dynamic> _checked(Response<dynamic> response){
    final code=response.statusCode??0;
    if (code == 403) session.reportAuthorizationDenied();
    if(code<200 || code>=300){
      final payload=response.data;
      final name=payload is Map ? (payload['errorCode']??payload['code']??'api_error').toString():'api_error';
      throw FableApiException(code,name,details:payload);
    }
    return response;
  }
  @override
  Future<Response<dynamic>> execute(String operationId,{Map<String,dynamic>? path,
    Map<String,dynamic>? query,Object? body,CancelToken? cancelToken,String? ifMatch}) =>
      request(operationId,path:path,query:query,body:body,cancelToken:cancelToken,ifMatch:ifMatch);
  @override
  void dispose()=>_dio.close(force:true);
}
/// Compatibility wrapper for apps generated by older RCs.
/// New integrations should depend on BackendApiGateway or UnifiedApiClient.
class FableApiClient extends UnifiedApiClient {
  FableApiClient({required super.baseUri,required super.contract,required super.session,
    super.refreshSession,super.credentialProvider,super.adapter,super.allowHttpForLocalDevelopment,super.client,super.retryPolicy});
}

class FableApiException implements Exception {
  FableApiException(this.status,this.code,{this.message,this.details});
  final int status;final String code;final String? message;final Object? details;
  @override String toString()=> 'FableApiException($status, $code)';
}
