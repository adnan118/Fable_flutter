import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'backend_transport_adapter.dart';
import 'fable_api.dart';
import 'fable_contract.dart';
import 'fable_session.dart';

/// An authenticated Fable mobile session uses only the exported backend Auth contract.
/// Refresh rotation is single-flight in FableApiClient. Network errors during refresh
/// never destroy the local session; only definitive authorization failures do.
class FableAuthGateway implements BackendApiGateway {
  FableAuthGateway({
    required Uri baseUri,
    required FableContract contract,
    FableSecureSession? secureSession,
    bool allowHttpForLocalDevelopment = false,
    Dio? client,
  }) : session = secureSession ?? FableSecureSession(namespace: _sessionNamespace(baseUri,contract)) {
    _contract = contract;
    _api = FableApiClient(
      baseUri: baseUri,
      contract: contract,
      session: session,
      client: client,
      allowHttpForLocalDevelopment: allowHttpForLocalDevelopment,
      refreshSession: _refreshSession,
      adapter: FableTransportAdapter(catalog: contract),
    );
  }

  static String _sessionNamespace(Uri base, FableContract contract) =>
    'fable.${sha256.convert(utf8.encode('${base.origin}|${contract.projectName}')).toString().substring(0,32)}';

  final FableSecureSession session;
  late final FableApiClient _api;
  late final FableContract _contract;

  /// A two-factor challenge does not create a session. It needs a separate
  /// challenge-completion flow before credentials can be treated as authenticated.
  Future<FableLoginOutcome> login({
    required String identifier,
    required String password,
    required String platform,
  }) async {
    final id = identifier.trim();
    if (id.isEmpty || password.isEmpty) {
      throw ArgumentError('Credentials are required');
    }
    final identityAtStart = session.identityRevision;
    final response = await _api.request('auth.login', authorized: false, body: {
      'identifier': id,
      'password': password,
      'clientType': 'flutter',
      'installationId': await session.installationId(),
      'platform': platform,
    });
    final data = _payload(response.data);
    if (data['requiresTwoFactor'] == true) {
      final challenge = data['twoFactorToken'];
      if (challenge is! String || challenge.isEmpty) {
        throw const FormatException('Missing second-factor challenge');
      }
      if (challenge.length < 32 || challenge.length > 512) {
        throw const FormatException('Invalid second-factor challenge');
      }
      final methods=(data['methods'] is List)
        ? (data['methods'] as List).whereType<String>().toList(growable:false)
        : <String>[];
      return FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge._(
        challenge, identityAtStart, methods, platform,
        DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
      ));
    }
    final saved = await _saveNewSession(data, newLogin: true, expectedIdentity: identityAtStart);
    if (!saved) throw FableApiException(409, 'session_changed_discard_response');
    return FableLoginOutcome.authenticated();
  }

  /// Request an OTP bound to the pending first-factor challenge. The challenge
  /// is transient memory-only data; it must never be persisted or logged.
  Future<String> requestSecondFactor(FableSecondFactorChallenge pending,
      {String? preferredChannel}) async {
    _checkPending(pending,'auth.2fa.login.request');
    if (preferredChannel != null && !const {'EMAIL','PHONE'}.contains(preferredChannel)) {
      throw ArgumentError('Unsupported second-factor channel');
    }
    final response=await _api.request('auth.2fa.login.request',authorized:false,body:{
      'twoFactorToken': pending._token,
      'clientType':'flutter',
      'installationId':await session.installationId(),
      if(preferredChannel!=null)'preferredChannel':preferredChannel,
    });
    if(session.identityRevision != pending._identityRevision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=_payload(response.data);
    final challengeId=data['challengeId'];
    if(challengeId is! String || !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      ).hasMatch(challengeId)) {
      throw const FormatException('Invalid second-factor OTP challenge');
    }
    return challengeId;
  }

  /// Consume a verified OTP once and create a session only on a successful
  /// backend completion. Replays and account switches fail closed.
  Future<void> completeSecondFactor(FableSecondFactorChallenge pending,{
      required String challengeId,required String code}) async {
    _checkPending(pending,'auth.2fa.login.complete');
    if(!RegExp(r'^\d{4,10}$').hasMatch(code)) {
      throw ArgumentError('Invalid OTP format');
    }
    if(!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(challengeId)) {
      throw ArgumentError('Invalid OTP challenge ID');
    }
    final response=await _api.request('auth.2fa.login.complete',authorized:false,body:{
      'twoFactorToken':pending._token,'challengeId':challengeId,'code':code,
      'clientType':'flutter','installationId':await session.installationId(),
      'platform':pending.platform,
    });
    final saved=await _saveNewSession(_payload(response.data),newLogin:true,
      expectedIdentity:pending._identityRevision);
    if(!saved)throw FableApiException(409,'session_changed_discard_response');
  }

  void _checkPending(FableSecondFactorChallenge pending,String operation){
    if(!_contract.supports(operation))throw StateError(
      'Second-factor operation missing from verified backend contract: $operation');
    if(session.identityRevision!=pending._identityRevision)throw FableApiException(
      409,'session_changed_discard_response');
    if(pending.expiresAt!=null && !pending.expiresAt!.isAfter(DateTime.now().toUtc())) {
      throw FableApiException(401,'second_factor_challenge_expired');
    }
  }

  Future<bool> _refreshSession() async {
    final identityAtStart = session.identityRevision;
    final token = await session.refreshToken;
    if (token == null || token.isEmpty) return false;
    try {
      final response = await _api.request('auth.refresh', authorized: false, body: {
        'refreshToken': token,
        'installationId': await session.installationId(),
        'clientType': 'flutter',
      });
      if (session.identityRevision != identityAtStart) {
        // Logout or a different login happened while refresh was in flight.
        return false;
      }
      return await _saveNewSession(_payload(response.data), expectedIdentity: identityAtStart,
        expectedRefreshToken: token);
    } on FableApiException catch (error) {
      // A definite authentication failure invalidates this session. Server
      // failure, timeout and disconnection are transient and are rethrown.
      if (error.status == 401 || error.status == 403) {
        await session.clearSessionIfIdentity(identityAtStart, expectedRefreshToken: token);
        return false;
      }
      rethrow;
    }
  }

  /// Logout always clears local credentials. false means remote revocation
  /// was not confirmed; it must not be presented as server-side success.
  Future<bool> logout() async {
    final identityAtStart = session.identityRevision;
    var revokedOnServer = false;
    try {
      if (await session.accessToken != null) {
        await _api.request('auth.logout');
        revokedOnServer = true;
      }
    } catch (_) {
      // Device sign-out is still necessary even when the server is unreachable.
    } finally {
      await session.clearSessionIfIdentity(identityAtStart);
    }
    return revokedOnServer;
  }

  /// Contract-declared account snapshot, distinct from project-specific Profile.
  /// Presentation-only change; no email/phone/username/security edits.
  Future<FableAccountSummary> updateAccountDisplayName(String name) async {
    if (!_contract.supports('account.displayName.update')) {
      throw StateError('Backend has not exported account.displayName.update');
    }
    final trimmed=name.trim();
    if(trimmed.isEmpty || trimmed.length>100 ||
        RegExp(r'[\x00-\x1F\x7F<>]').hasMatch(trimmed)) {
      throw ArgumentError('Invalid display name');
    }
    final response=await _api.request('account.displayName.update',body:{'displayName':trimmed});
    return FableAccountSummary.fromMap(_payload(response.data));
  }

  Future<FableAccountSummary> account() async {
    if (!_contract.supports('account.me')) {
      throw StateError('Backend has not exported account.me');
    }
    final response = await _api.request('account.me');
    return FableAccountSummary.fromMap(_payload(response.data));
  }

  /// Read the effective policy from the deployed backend; do not infer it from
  /// a static build-time default or from a local account/device count.
  Future<FableSessionPolicy> loadSessionPolicy() async {
    if (!_contract.supports('auth.session-policy')) {
      throw StateError('Backend has not exported auth.session-policy');
    }
    final response=await _api.request('auth.session-policy',authorized:false);
    return FableSessionPolicy.fromMap(_payload(response.data));
  }

  Future<Object?> sessions() async {
    if(!_contract.supports('auth.sessions'))
      throw StateError('Backend did not export auth.sessions');
    final response=await _api.request('auth.sessions');
    return response.data;
  }

  /// Actual Backend sessions list, not a locally inferred device count.
  Future<List<FableActiveSession>> listActiveSessions() async {
    final response=await sessions();
    final payload=response is Map && response.containsKey('data')
      ? response['data'] : response;
    if(payload is! List || payload.length>10000)
      throw const FormatException('Invalid active sessions response');
    final parsed=<FableActiveSession>[];
    final identifiers=<String>{};
    for(final entry in payload){
      if(entry is! Map)throw const FormatException('Invalid session entry');
      final record=FableActiveSession.fromMap(Map<String,dynamic>.from(entry));
      if(!identifiers.add(record.id))
        throw const FormatException('Duplicate session identity');
      parsed.add(record);
    }
    return List<FableActiveSession>.unmodifiable(parsed);
  }

  static Map<String, dynamic> _payload(Object? value) {
    final envelope = value is Map ? value : null;
    final candidate = envelope != null && envelope['data'] is Map
        ? envelope['data']
        : envelope;
    if (candidate is! Map) {
      throw const FormatException('Expected object from auth backend');
    }
    return Map<String, dynamic>.from(candidate);
  }

  Future<bool> _saveNewSession(Map<String, dynamic> payload, {bool newLogin = false,
      required int expectedIdentity, String? expectedRefreshToken}) async {
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    if (access is! String || access.isEmpty || access.length > 8192 ||
        access.contains(RegExp(r'[\r\n\x00-\x1f\x7f]')) ||
        refresh is! String || !RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(refresh)) {
      throw const FormatException('Invalid session response from auth backend');
    }
    if (newLogin) {
      return session.replaceTokensIfIdentity(expectedIdentity: expectedIdentity,
        accessToken: access, refreshToken: refresh);
    } else {
      return session.saveTokensIfIdentity(expectedIdentity: expectedIdentity,
        accessToken: access, refreshToken: refresh,
        expectedRefreshToken: expectedRefreshToken);
    }
  }

  /// Shared verified-operation transport for optional Fable capabilities.
  /// Feature repositories only depend on BackendApiGateway; this adapter retains
  /// the same auth/session/refresh semantics as login, without guessing routes.
  Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  }) => _api.execute(operationId,path:path,query:query,body:body,cancelToken:cancelToken,ifMatch:ifMatch);
  void dispose() => _api.dispose();
}

/// Never render/log the token. Keep this object only in the login screen state.
class FableSecondFactorChallenge {
  const FableSecondFactorChallenge._(this._token,this._identityRevision,
    this.methods,this.platform,this.expiresAt);
  final String _token;
  final int _identityRevision;
  final List<String> methods;
  final String platform;
  final DateTime? expiresAt;
}

class FableLoginOutcome {
  const FableLoginOutcome._(this.authenticated,this.requiresTwoFactor,this.secondFactor);
  const FableLoginOutcome.authenticated() : this._(true,false,null);
  const FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge challenge) :
    this._(false,true,challenge);
  final bool authenticated;
  final bool requiresTwoFactor;
  final FableSecondFactorChallenge? secondFactor;
}

/// Only the presentation-safe, authenticated account fields of the Fable core.
/// This is intentionally NOT a domain Profile. The API response is whitelisted.
class FableAccountSummary {
  const FableAccountSummary({required this.id,this.displayName,this.username,
    this.email,this.phone,this.locale,this.timezone});
  final String id;
  final String? displayName,username,email,phone,locale,timezone;

  static FableAccountSummary fromMap(Map<String,dynamic> data) {
    final id=data['id'];
    if(id is! String || id.isEmpty || id.length>191) {
      throw const FormatException('Invalid account identity');
    }
    String? field(String key,int max) {
      final value=data[key];
      if(value==null)return null;
      if(value is! String || value.length>max || value.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
        throw const FormatException('Malformed account presentation field');
      }
      return value;
    }
    return FableAccountSummary(id:id,displayName:field('displayName',191),
      username:field('username',64),email:field('email',191),
      phone:field('phone',32),locale:field('locale',16),timezone:field('timezone',64));
  }
}


/// Public presentation fields returned by GET /auth/sessions.
/// Never stores bearer/refresh tokens, installation secrets or security proofs.
class FableActiveSession {
  const FableActiveSession({
    required this.id,required this.isCurrent,required this.createdAt,
    required this.expiresAt,this.lastUsedAt,this.displayName,this.deviceName,
    this.platform,this.clientType,this.appVersion,
  });
  final String id;
  final bool isCurrent;
  final DateTime createdAt,expiresAt;
  final DateTime? lastUsedAt;
  final String? displayName,deviceName,platform,clientType,appVersion;

  factory FableActiveSession.fromMap(Map<String,dynamic> source){
    final id=source['id'];
    if(id is! String ||
       !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$').hasMatch(id))
      throw const FormatException('Invalid active session UUID');
    if(source['isCurrent'] is! bool)
      throw const FormatException('Missing active session current state');
    DateTime parseDate(String key){
      final value=source[key];
      if(value is! String || value.length>64)
        throw FormatException('Invalid session date: $key');
      final parsed=DateTime.tryParse(value)?.toUtc();
      if(parsed==null)throw FormatException('Invalid session date: $key');
      return parsed;
    }
    String? optional(String key,int max){
      final value=source[key];
      if(value==null)return null;
      if(value is! String || value.length>max ||
         value.contains(RegExp(r'[\x00-\x1F\x7F]')))
        throw FormatException('Invalid session presentation field: $key');
      return value;
    }
    final createdAt=parseDate('createdAt'),expiresAt=parseDate('expiresAt');
    final lastUsed=source['lastUsedAt']==null ? null : parseDate('lastUsedAt');
    return FableActiveSession(
      id:id,isCurrent:source['isCurrent'] as bool,
      createdAt:createdAt,expiresAt:expiresAt,lastUsedAt:lastUsed,
      displayName:optional('displayName',191),
      deviceName:optional('deviceName',191),platform:optional('platform',64),
      clientType:optional('clientType',64),appVersion:optional('appVersion',64),
    );
  }
}
