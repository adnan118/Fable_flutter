import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'backend_transport_adapter.dart';
import 'fable_api.dart';
import 'fable_contract.dart';
import 'fable_session.dart';

/// المصادقة هنا تخص Fable فقط وتستخدم عمليات Auth المصدّرة لا مسارات متوقعة.
/// لا نحذف الجلسة عند Timeout/5xx، بل عند فشل صلاحية نهائي موثّق.
/// تفاصيل الأربعين عملية المتبقية: docs/integrations/FABLE-FLUTTER-PARITY-MASTER.ar.md
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

  /// لا يكفي تطابق operationId: نطابق مسار Fable وطريقته وحدّ المصادقة
  /// قبل إرسال كلمة مرور أو Refresh Token أو عرض بيانات الجلسات.
  /// Backend الآخر يستخدم Catalog/Gateway خاصاً به، ولا يمر بهذه الدالة.
  bool _supportsAuthOperation(String id, String method, String path,
      {required bool requiresAuth}) {
    final operation = _contract.operations[id];
    return operation != null &&
        operation.method == method &&
        operation.path == path &&
        operation.requiresAuth == requiresAuth &&
        operation.enforceAuth &&
        operation.credentialHeader == null;
  }

  void _requireAuthOperation(String id, String method, String path,
      {required bool requiresAuth}) {
    if (!_supportsAuthOperation(
      id, method, path, requiresAuth: requiresAuth,
    )) {
      throw StateError('Fable auth operation is missing or mismatched: $id');
    }
  }

  /// A two-factor challenge does not create a session. It needs a separate
  /// challenge-completion flow before credentials can be treated as authenticated.
  Future<FableLoginOutcome> login({
    required String identifier,
    required String password,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) async {
    final id = identifier.trim();
    if (id.isEmpty || password.isEmpty) {
      throw ArgumentError('Credentials are required');
    }
    // معلومات الجهاز اختيارية، لا تمثل إثبات هوية ولا موقع GPS.
    // نتحقق منها قبل الاتصال وفق حدود LoginDto الصادرة من Fable.
    final device=_validatedDeviceMetadata(platform:platform,
      deviceName:deviceName,appVersion:appVersion);
    _requireAuthOperation('auth.login', 'POST', '/auth/login', requiresAuth: false);
    final identityAtStart = session.identityRevision;
    final response = await _api.request('auth.login', authorized: false, body: {
      'identifier': id,
      'password': password,
      'clientType': 'flutter',
      'installationId': await session.installationId(),
      ...device,
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
      // لا نعرض طريقة تحقق إلا إذا أعلن عنها Backend Fable صراحة.
      final rawMethods=data['methods'];
      if(rawMethods is! List || rawMethods.isEmpty || rawMethods.length>2 ||
         rawMethods.any((m)=>m is! String ||
           !const <String>{'EMAIL_OTP','PHONE_OTP'}.contains(m)) ||
         rawMethods.toSet().length!=rawMethods.length) {
        throw const FormatException('Invalid second-factor method list');
      }
      final methods=List<String>.unmodifiable(rawMethods.cast<String>());
      final challengeExpires=_expiresAt(data['expiresAt'],
        context:'second-factor challenge');
      if(session.identityRevision!=identityAtStart) {
        throw FableApiException(409,'session_changed_discard_response');
      }
      return FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge._(
        challenge, identityAtStart, methods, device, challengeExpires,
      ));
    }
    // لا نعامل Session مفروضة لتغيير كلمة المرور كدخول طبيعي.
    // هذا الحقل إلزامي في استجابة Fable RC66؛ غيابه يوقف حفظ التوكن.
    final mandatoryChange = _requiredPasswordChangeState(data);
    final saved = await _saveNewSession(data, newLogin: true, expectedIdentity: identityAtStart);
    if (!saved) throw FableApiException(409, 'session_changed_discard_response');
    return FableLoginOutcome.authenticated(mustChangePassword: mandatoryChange);
  }

  /// Request an OTP bound to the pending first-factor challenge. The challenge
  /// is transient memory-only data; it must never be persisted or logged.
  Future<String> requestSecondFactor(FableSecondFactorChallenge pending,
      {String? preferredChannel}) async =>
    (await requestSecondFactorDetails(pending,
      preferredChannel:preferredChannel)).challengeId;

  /// تفاصيل طلب OTP المصدرية: الوقت ونوع التحقق من الخادم، بلا تخمين.
  /// نترك واجهة String القديمة للتوافق مع المشاريع السابقة فقط.
  Future<FableSecondFactorOtpRequest> requestSecondFactorDetails(
      FableSecondFactorChallenge pending,{String? preferredChannel}) async {
    _checkPending(pending,'auth.2fa.login.request');
    if (preferredChannel != null && !const {'EMAIL','PHONE'}.contains(preferredChannel)) {
      throw ArgumentError('Unsupported second-factor channel');
    }
    if(preferredChannel!=null &&
       !pending.methods.contains(preferredChannel=='EMAIL'?'EMAIL_OTP':'PHONE_OTP')) {
      throw ArgumentError('Unadvertised second-factor channel');
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
    final method=data['method'];
    if(data['requiresTwoFactor']!=true ||
       method is! String || !pending.methods.contains(method) ||
       (preferredChannel!=null &&
         method!=(preferredChannel=='EMAIL'?'EMAIL_OTP':'PHONE_OTP'))) {
      throw const FormatException('Invalid Fable OTP method/authorization');
    }
    final channel=data['channel'];
    if(channel is! String ||
       channel!=(method=='EMAIL_OTP'?'EMAIL':'PHONE')) {
      throw const FormatException('Mismatched Fable OTP delivery channel');
    }
    final otpExpires=_expiresAt(data['expiresAt'],context:'OTP code');
    final loginExpires=_expiresAt(data['twoFactorExpiresAt'],
      context:'second-factor login');
    // لا نقبل مهلة جديدة تتجاوز المدة الأصلية لتحدي العامل الأول.
    if(loginExpires.isAfter(pending.expiresAt)) {
      throw const FormatException('Unexpected extension of first-factor challenge');
    }
    final masked=data['destination'];
    if(masked!=null && (masked is! String || masked.length>191 ||
       RegExp(r'[\x00-\x1F\x7F]').hasMatch(masked))) {
      throw const FormatException('Invalid masked OTP destination');
    }
    return FableSecondFactorOtpRequest._(challengeId,method,channel,
      otpExpires,loginExpires,masked as String?);
  }

  /// Consume a verified OTP once and create a session only on a successful
  /// backend completion. Replays and account switches fail closed.
  Future<FableLoginOutcome> completeSecondFactor(FableSecondFactorChallenge pending,{
      required String challengeId,required String code}) async {
    _checkPending(pending,'auth.2fa.login.complete');
    if(!RegExp(r'^\d{4,10}$').hasMatch(code)) {
      throw ArgumentError('Invalid OTP format');
    }
    if(!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$').hasMatch(challengeId)) {
      throw ArgumentError('Invalid OTP challenge ID');
    }
    final response=await _api.request('auth.2fa.login.complete',authorized:false,body:{
      'twoFactorToken':pending._token,'challengeId':challengeId,'code':code,
      'clientType':'flutter','installationId':await session.installationId(),
      ...pending.device,
    });
    final payload=_payload(response.data);
    // إكمال العامل الثاني يصدر Session كاملة؛ تنطبق عليها سياسة تغيير
    // كلمة المرور تماماً كما في Login العادي، ولا يجوز تجاوزها بعد OTP.
    final mandatoryChange=_requiredPasswordChangeState(payload);
    final saved=await _saveNewSession(payload,newLogin:true,
      expectedIdentity:pending._identityRevision);
    if(!saved)throw FableApiException(409,'session_changed_discard_response');
    return FableLoginOutcome.authenticated(mustChangePassword:mandatoryChange);
  }

  void _checkPending(FableSecondFactorChallenge pending,String operation){
    // لا يكفي operationId عند تمرير رمز OTP أو TwoFactorToken:
    // يجب التحقق من طريقة ومسار العمليات العامة في RC66.
    switch(operation){
      case 'auth.2fa.login.request':
        _requireAuthOperation(operation,'POST','/auth/2fa/login/request',
          requiresAuth:false);
        break;
      case 'auth.2fa.login.complete':
        _requireAuthOperation(operation,'POST','/auth/2fa/login/complete',
          requiresAuth:false);
        break;
      default:
        throw StateError('Unsupported second-factor operation: $operation');
    }
    if(session.identityRevision!=pending._identityRevision)throw FableApiException(
      409,'session_changed_discard_response');
    if(!pending.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw FableApiException(401,'second_factor_challenge_expired');
    }
  }

  // معلومات العرض لا تحل محل Installation ID المرتبط فعلياً بالجلسة.
  static Map<String,String> _validatedDeviceMetadata({
      required String platform,String? deviceName,String? appVersion}) {
    if(platform.isEmpty || platform.length>64 ||
       !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(platform)) {
      throw ArgumentError('Invalid device platform');
    }
    String? optional(String? value,int max,String field){
      if(value==null)return null;
      final clean=value.trim();
      if(clean.isEmpty || clean.length>max ||
         RegExp(r'[\x00-\x1f\x7f]').hasMatch(clean)) {
        throw ArgumentError('Invalid $field');
      }
      return clean;
    }
    final name=optional(deviceName,191,'deviceName');
    final version=optional(appVersion,64,'appVersion');
    return Map<String,String>.unmodifiable({
      'platform':platform,
      if(name!=null)'deviceName':name,
      if(version!=null)'appVersion':version,
    });
  }

  Future<bool> _refreshSession() async {
    _requireAuthOperation('auth.refresh', 'POST', '/auth/refresh', requiresAuth: false);
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
      if (await session.accessToken != null && _supportsAuthOperation(
        'auth.logout', 'POST', '/auth/logout', requiresAuth: true,
      )) {
        final response=await _api.request('auth.logout');
        // الوصول إلى HTTP 200 لا يثبت إبطال الجلسة. Fable يعيد revoked.
        // لا نخلط نجاح حذف اعتماد الهاتف مع نجاح الخادم.
        revokedOnServer=_payload(response.data)['revoked']==true;
      }
    } catch (_) {
      // Device sign-out is still necessary even when the server is unreachable.
    } finally {
      await session.clearSessionIfIdentity(identityAtStart);
    }
    return revokedOnServer;
  }

  /// تغيير كلمة المرور عملية حساسة في عقد Fable؛ ليست تعديل ملف شخصي.
  /// يتحقق الخادم من كلمة المرور الحالية ومن سياسة التعقيد وتاريخ الإعادة،
  /// وعند نجاحه يلغي جميع الجلسات بما فيها الحالية. لذلك نمسح محلياً فقط
  /// جلسة الهوية التي بدأت العملية، ولا نمسح جلسة مستخدم دخل أثناء الطلب.
  /// المصدر: docs/integrations/FABLE-BACKEND-WIDE-DECISIONS-RC81.ar.md
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final operation=_contract.operations['auth.change-password'];
    if(operation==null||operation.method!='POST'||
       operation.path!='/auth/change-password'||!operation.requiresAuth||
       operation.credentialHeader!=null) {
      throw StateError('Authenticated change-password operation not exported by Fable');
    }
    // لا نفرض سياسة تعقيد محلية: سياسة الخادم قابلة للتغيير؛ تُعرض أخطاؤه.
    if(currentPassword.isEmpty||newPassword.isEmpty||
       currentPassword.length>1024||newPassword.length>1024||
       currentPassword==newPassword) {
      throw ArgumentError('Password fields are invalid or unchanged');
    }
    final revision=session.identityRevision;
    final response=await _api.request(operation.id,body:{
      'currentPassword':currentPassword,'newPassword':newPassword,
    });
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final payload=_payload(response.data);
    if(payload['changed']!=true)
      throw const FormatException('Backend did not confirm password change');
    // لا يوجد Refresh أو إعادة تسجيل تلقائي: Backend ألغى كل الجلسات.
    final cleared=await session.clearSessionIfIdentity(revision);
    if(!cleared)
      throw FableApiException(409,'session_changed_discard_response');
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
    _requireAuthOperation('auth.session-policy', 'GET', '/auth/session-policy',
      requiresAuth: false);
    final response=await _api.request('auth.session-policy',authorized:false);
    final data=_payload(response.data);
    // الخادم الحالي يعلن هذه السياسة دائماً؛ لا نستنتجها من إعداد Wizard قديم.
    if (data['onePerInstallation'] is! bool) {
      throw const FormatException('Backend did not declare onePerInstallation');
    }
    return FableSessionPolicy.fromMap(data);
  }

  /// المنطقة الزمنية تخص عرض الجلسة الحالية فقط، لا الحجز أو المواعيد.
  /// Fable يفرض التحقق الفعلي من IANA timezone، ولا نخمنه من جهاز المستخدم.
  /// docs/integrations/FABLE-AUTH-BASELINE-RC82.ar.md
  bool get supportsSessionTimeZone {
    return _supportsAuthOperation('auth.session.timezone', 'POST',
      '/auth/session/timezone', requiresAuth: true);
  }

  Future<String> updateSessionTimeZone(String zone) async {
    if(!supportsSessionTimeZone)
      throw StateError('Backend did not export authenticated auth.session.timezone');
    // يفحص العميل شكل الإدخال فقط. المرجع النهائي لـIANA هو Backend.
    final value=zone.trim();
    if(value.isEmpty||value.length>64||
       !RegExp(r'^[A-Za-z0-9_+./-]+$').hasMatch(value)||
       value.contains('..')||value.startsWith('/')||value.endsWith('/')){
      throw ArgumentError('Invalid time zone input');
    }
    final revision=session.identityRevision;
    final response=await _api.request('auth.session.timezone',
      body:{'timeZone':value});
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final result=_payload(response.data);
    if(result['updated']!=true||result['timeZone']!=value)
      throw const FormatException('Backend did not confirm session time zone');
    return value;
  }

  Future<Object?> sessions() async {
    _requireAuthOperation('auth.sessions', 'GET', '/auth/sessions',
      requiresAuth: true);
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

  static final _uuid=RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    caseSensitive:false);

  String _route(String path,String method) {
    final matching=_contract.operations.values.where(
      (op)=>op.path==path && op.method==method && op.requiresAuth &&
        op.credentialHeader==null).toList();
    if(matching.length!=1)throw StateError('Backend did not export a unique authorized $method $path operation');
    return matching.single.id;
  }
  bool get canRevokeOtherSessions => _contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/{id}/revoke'&&op.method=='POST'&&op.requiresAuth);
  bool get canRequestSensitiveProof => _contract.operations.values.any(
    (op)=>op.path=='/auth/otp/request'&&op.method=='POST'&&op.requiresAuth) &&
    _contract.operations.values.any(
    (op)=>op.path=='/auth/otp/verify'&&op.method=='POST'&&op.requiresAuth);

  Future<String> requestSensitiveActionOtp() async {
    final rev=session.identityRevision;
    final response=await _api.request(_route('/auth/otp/request','POST'),
      body:{'purpose':'SENSITIVE_ACTION'});
    if(session.identityRevision!=rev)throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),id=data['challengeId'];
    if(id is! String || !_uuid.hasMatch(id))
      throw const FormatException('Backend returned an invalid sensitive-action OTP challenge');
    return id;
  }

  /// A public-password-reset flow is enabled only when the *three exact*
  /// Backend Fable operations are exported with the right auth boundary.
  /// Other Backend has its own catalog; do not import these Fable routes.
  bool get canResetPasswordWithPublicOtp =>
      _supportsAuthOperation('auth.otp.public.request','POST',
        '/auth/otp/public/request',requiresAuth:false) &&
      _supportsAuthOperation('auth.otp.public.verify','POST',
        '/auth/otp/public/verify',requiresAuth:false) &&
      _supportsAuthOperation('auth.password.reset','POST',
        '/auth/password/reset',requiresAuth:false);

  /// Server returns QUEUED, not confirmation of remote email/SMS delivery.
  /// A rejected/unknown identifier is a real backend failure; do not show
  /// a fabricated success or expose any internal rejection reason.
  Future<FablePasswordResetChallenge> requestPasswordResetOtp({
    required String identifier,String? preferredChannel,
  }) async {
    final id=identifier.trim();
    if(id.isEmpty||id.length>191)throw ArgumentError('Invalid reset identifier');
    if(preferredChannel!=null &&
        !const {'EMAIL','PHONE'}.contains(preferredChannel)) {
      throw ArgumentError('Invalid OTP channel');
    }
    _requireAuthOperation('auth.otp.public.request','POST',
      '/auth/otp/public/request',requiresAuth:false);
    final rev=session.identityRevision;
    final response=await _api.request('auth.otp.public.request',
      authorized:false,body:{
        'purpose':'PASSWORD_RESET','identifier':id,
        if(preferredChannel!=null)'preferredChannel':preferredChannel,
      });
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),challengeId=data['challengeId'];
    if(data['accepted']!=true||data['deliveryStatus']!='QUEUED'||
        challengeId is! String||!_uuid.hasMatch(challengeId)){
      throw const FormatException('Backend did not queue a valid password-reset OTP');
    }
    return FablePasswordResetChallenge._(
      challengeId,_expiresAt(data['expiresAt'],context:'password-reset OTP'),
      rev,this);
  }

  /// Proof is purpose-bound to PASSWORD_RESET and one Backend challenge.
  /// This method does not start a new authenticated session.
  Future<FablePasswordResetProof> verifyPasswordResetOtp(
      FablePasswordResetChallenge pending,String code) async {
    if(!identical(pending._owner,this)||
       session.identityRevision!=pending._identityRevision||
       !pending.expiresAt.isAfter(DateTime.now().toUtc())){
      throw StateError('Password reset challenge is expired or belongs to another session');
    }
    if(!RegExp(r'^[0-9]{6,10}
  /// It is a short-lived proof consumed atomically by the protected backend operation.
  Future<FableVerifiedSensitiveProof> verifySensitiveActionOtp(String challengeId,String code) async {
    if(!_uuid.hasMatch(challengeId)||!RegExp(r'^[0-9]{6,10}
      throw ArgumentError('Invalid OTP challenge or code');
    final rev=session.identityRevision;
    final response=await _api.request(_route('/auth/otp/verify','POST'),
      body:{'challengeId':challengeId,'code':code});
    if(session.identityRevision!=rev)throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true || data['challengeId']!=challengeId ||
      data['purpose']!='SENSITIVE_ACTION')
      throw const FormatException('Backend did not verify the expected sensitive-action proof');
    return FableVerifiedSensitiveProof._(challengeId,rev);
  }

  Future<bool> revokeOtherSession(String sessionId,{FableVerifiedSensitiveProof? proof}) async {
    if(!_uuid.hasMatch(sessionId))throw ArgumentError('Invalid session ID');
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(
      _route('/auth/sessions/{id}/revoke','POST'),
      path:{'id':sessionId},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['sessionId']!=sessionId || data['revoked'] is! bool)
      throw const FormatException('Invalid Backend session revocation response');
    // Never silently sign out a different local identity.
    return data['revoked'] as bool;
  }
  bool get canRevokeSelectedSessions => _contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/revoke-selected' && op.method=='POST' &&
      op.requiresAuth && op.credentialHeader==null);

  /// Server-owned bulk revocation. Never loop revoke-one calls (each may
  /// require a distinct consumed step-up proof).
  Future<List<String>> revokeSelectedSessions(List<String> ids,{
    FableVerifiedSensitiveProof? proof,
  })async {
    final selected=ids.toSet().toList(growable:false);
    if(selected.isEmpty||selected.length>100||selected.any((id)=>!_uuid.hasMatch(id)))
      throw ArgumentError('Select 1-100 distinct, valid active session IDs');
    final revision=session.identityRevision;
    if(proof!=null&&proof._identityRevision!=revision)
      throw StateError('Security proof belongs to another identity');
    final response=await _api.request(
      _route('/auth/sessions/revoke-selected','POST'),
      body:{'sessionIds':selected},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    final revoked=data['sessionIds'],current=data['currentSessionRevoked'];
    if(revoked is! List||revoked.any((id)=>id is! String||
        !selected.contains(id)) ||
       revoked.length!=revoked.toSet().length||
       data['revoked'] is! int||data['revoked']!=revoked.length||
       current is! bool)
      throw const FormatException('Backend returned an invalid selected-session revocation');
    if(current)await session.clearSessionIfIdentity(revision);
    return List<String>.unmodifiable(revoked.cast<String>());
  }

  Future<int> revokeAllSessions({FableVerifiedSensitiveProof? proof}) async {
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(_route('/auth/logout-all','POST'),
      securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),count=data['revoked'];
    if(count is! int||count<0)throw const FormatException('Invalid logout-all response');
    await session.clearSessionIfIdentity(rev);
    return count;
  }

  /// Explicit Fable entity-context opt-in for a verified, protected project
  /// operation. Never persist the entity header or propagate it across Backends.
  Future<Response<dynamic>> executeInManagedEntity(String operationId,String managedEntityId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body
  }) {
    if(!_uuid.hasMatch(managedEntityId))throw ArgumentError('Invalid managed entity ID');
    return _api.request(operationId,path:path,query:query,body:body,
      managedEntityId:managedEntityId);
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

  /// يجب رفض اعتماد انتهت مدته بالفعل، ولا نتخيل انتهاءً من ساعة العميل
  /// عندما يغيب expiresAt من استجابة Fable. لا نعيد إرسال Refresh تلقائياً.
  static DateTime _expiresAt(Object? value,{required String context}) {
    if(value is! String || value.length>64 ||
       !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
       !value.endsWith('Z')) {
      throw FormatException('Missing UTC expiration in $context');
    }
    final time=DateTime.tryParse(value)?.toUtc();
    if(time==null || !time.isAfter(DateTime.now().toUtc())) {
      throw FormatException('Expired or invalid $context');
    }
    return time;
  }

  static bool _requiredPasswordChangeState(Map<String,dynamic> payload) {
    final required=payload['mustChangePassword'];
    if(required is! bool) {
      throw const FormatException('Missing mustChangePassword in Fable login response');
    }
    return required;
  }

  Future<bool> _saveNewSession(Map<String, dynamic> payload, {bool newLogin = false,
      required int expectedIdentity, String? expectedRefreshToken}) async {
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    // فشل التاريخ يمنع حفظ أسرار جلسة منتهية؛ JWT/Session DB يظلان
    // مصدر الصلاحية النهائي، ولا نعد هذا اختباراً لتكامل Backend الحي.
    _expiresAt(payload['expiresAt'],context:'session');
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
    this.methods,this.device,this.expiresAt);
  final String _token;
  final int _identityRevision;
  final List<String> methods;
  /// نحتفظ بنفس بيانات الجهاز للعامل الثاني. لا نخزن Password أو OTP.
  final Map<String,String> device;
  final DateTime expiresAt;
}

/// بيانات تحدي OTP لا تتضمن الرمز نفسه، ونحتفظ بالعنوان المقنّع فقط.
class FableSecondFactorOtpRequest {
  const FableSecondFactorOtpRequest._(this.challengeId,this.method,this.channel,
    this.expiresAt,this.twoFactorExpiresAt,this.maskedDestination);
  final String challengeId,method,channel;
  final DateTime expiresAt,twoFactorExpiresAt;
  final String? maskedDestination;
}

class FableLoginOutcome {
  const FableLoginOutcome._(this.authenticated,this.requiresTwoFactor,
      this.secondFactor,this.mustChangePassword);
  const FableLoginOutcome.authenticated({required bool mustChangePassword}) :
    this._(true,false,null,mustChangePassword);
  const FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge challenge) :
    this._(false,true,challenge,false);
  final bool authenticated;
  final bool requiresTwoFactor;
  final FableSecondFactorChallenge? secondFactor;
  /// Fable يسمح في هذه الحالة فقط بـchange-password/logout حتى نجاح التغيير.
  /// هذا حقل صادر من الخادم، وليس تخميناً من Flutter أو اختياراً في Wizard.
  final bool mustChangePassword;
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
    this.platform,this.clientType,this.appVersion,this.securityState,
  });
  final String id;
  final bool isCurrent;
  final DateTime createdAt,expiresAt;
  final DateTime? lastUsedAt;
  final String? displayName,deviceName,platform,clientType,appVersion;
  /// حالة حماية الجلسة من Backend، وليست حكماً أمنياً محلياً من Flutter.
  final String? securityState;

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
    final security=source['securityState'];
    if(security!=null && (security is! String ||
        !const <String>{'ACTIVE','SUSPICIOUS','COMPROMISED'}.contains(security))) {
      throw const FormatException('Invalid backend session security state');
    }
    return FableActiveSession(
      id:id,isCurrent:source['isCurrent'] as bool,
      createdAt:createdAt,expiresAt:expiresAt,lastUsedAt:lastUsed,
      displayName:optional('displayName',191),
      deviceName:optional('deviceName',191),platform:optional('platform',64),
      clientType:optional('clientType',64),appVersion:optional('appVersion',64),
      securityState:security as String?,
    );
  }
}


/// A confirmed SENSITIVE_ACTION OTP, never serialized or stored in preferences.
/// Backend consumes the challenge on the first protected action if the session
/// itself does not already satisfy the recent AAL2 policy.
class FableVerifiedSensitiveProof {
  const FableVerifiedSensitiveProof._(this._challengeId,this._identityRevision);
  final String _challengeId;
  final int _identityRevision;
}
).hasMatch(code)){
      throw ArgumentError('Password reset OTP must be 6-10 digits');
    }
    _requireAuthOperation('auth.otp.public.verify','POST',
      '/auth/otp/public/verify',requiresAuth:false);
    final response=await _api.request('auth.otp.public.verify',
      authorized:false,body:{'challengeId':pending.challengeId,'code':code});
    if(session.identityRevision!=pending._identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true||data['challengeId']!=pending.challengeId||
       data['purpose']!='PASSWORD_RESET'){
      throw const FormatException('Backend OTP verification has wrong purpose or challenge');
    }
    return FablePasswordResetProof._(pending.challengeId,
      pending._identityRevision,this);
  }

  /// Server enforces password policy/history and revokes *all* sessions.
  /// A local gateway must not invent a new session or log/store the password.
  Future<FablePasswordResetResult> completePasswordReset(
      FablePasswordResetProof proof,{required String newPassword}) async {
    if(!identical(proof._owner,this)||
       session.identityRevision!=proof._identityRevision) {
      throw StateError('Reset proof belongs to another Fable identity or gateway');
    }
    if(newPassword.isEmpty||newPassword.length>1024){
      throw ArgumentError('Password reset DTO requires 1-1024 characters');
    }
    _requireAuthOperation('auth.password.reset','POST',
      '/auth/password/reset',requiresAuth:false);
    final response=await _api.request('auth.password.reset',
      authorized:false,body:{
        'challengeId':proof.challengeId,'newPassword':newPassword,
      });
    if(session.identityRevision!=proof._identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['changed']!=true||data['sessionsRevoked'] is! int||
       (data['sessionsRevoked'] as int)<0 ||
       data['twoFactorPreserved'] is! bool){
      throw const FormatException('Backend did not confirm password reset and session invalidation');
    }
    return FablePasswordResetResult(
      sessionsRevoked:data['sessionsRevoked'] as int,
      twoFactorPreserved:data['twoFactorPreserved'] as bool);
  }

  /// The verified challenge is never a new login, nor a reusable local grant.
  /// It is a short-lived proof consumed atomically by the protected backend operation.
  Future<FableVerifiedSensitiveProof> verifySensitiveActionOtp(String challengeId,String code) async {
    if(!_uuid.hasMatch(challengeId)||!RegExp(r'^[0-9]{4,10}$').hasMatch(code))
      throw ArgumentError('Invalid OTP challenge or code');
    final rev=session.identityRevision;
    final response=await _api.request(_route('/auth/otp/verify','POST'),
      body:{'challengeId':challengeId,'code':code});
    if(session.identityRevision!=rev)throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true || data['challengeId']!=challengeId ||
      data['purpose']!='SENSITIVE_ACTION')
      throw const FormatException('Backend did not verify the expected sensitive-action proof');
    return FableVerifiedSensitiveProof._(challengeId,rev);
  }

  Future<bool> revokeOtherSession(String sessionId,{FableVerifiedSensitiveProof? proof}) async {
    if(!_uuid.hasMatch(sessionId))throw ArgumentError('Invalid session ID');
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(
      _route('/auth/sessions/{id}/revoke','POST'),
      path:{'id':sessionId},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['sessionId']!=sessionId || data['revoked'] is! bool)
      throw const FormatException('Invalid Backend session revocation response');
    // Never silently sign out a different local identity.
    return data['revoked'] as bool;
  }
  bool get canRevokeSelectedSessions => _contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/revoke-selected' && op.method=='POST' &&
      op.requiresAuth && op.credentialHeader==null);

  /// Server-owned bulk revocation. Never loop revoke-one calls (each may
  /// require a distinct consumed step-up proof).
  Future<List<String>> revokeSelectedSessions(List<String> ids,{
    FableVerifiedSensitiveProof? proof,
  })async {
    final selected=ids.toSet().toList(growable:false);
    if(selected.isEmpty||selected.length>100||selected.any((id)=>!_uuid.hasMatch(id)))
      throw ArgumentError('Select 1-100 distinct, valid active session IDs');
    final revision=session.identityRevision;
    if(proof!=null&&proof._identityRevision!=revision)
      throw StateError('Security proof belongs to another identity');
    final response=await _api.request(
      _route('/auth/sessions/revoke-selected','POST'),
      body:{'sessionIds':selected},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    final revoked=data['sessionIds'],current=data['currentSessionRevoked'];
    if(revoked is! List||revoked.any((id)=>id is! String||
        !selected.contains(id)) ||
       revoked.length!=revoked.toSet().length||
       data['revoked'] is! int||data['revoked']!=revoked.length||
       current is! bool)
      throw const FormatException('Backend returned an invalid selected-session revocation');
    if(current)await session.clearSessionIfIdentity(revision);
    return List<String>.unmodifiable(revoked.cast<String>());
  }

  Future<int> revokeAllSessions({FableVerifiedSensitiveProof? proof}) async {
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(_route('/auth/logout-all','POST'),
      securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),count=data['revoked'];
    if(count is! int||count<0)throw const FormatException('Invalid logout-all response');
    await session.clearSessionIfIdentity(rev);
    return count;
  }

  /// Explicit Fable entity-context opt-in for a verified, protected project
  /// operation. Never persist the entity header or propagate it across Backends.
  Future<Response<dynamic>> executeInManagedEntity(String operationId,String managedEntityId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body
  }) {
    if(!_uuid.hasMatch(managedEntityId))throw ArgumentError('Invalid managed entity ID');
    return _api.request(operationId,path:path,query:query,body:body,
      managedEntityId:managedEntityId);
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

  /// يجب رفض اعتماد انتهت مدته بالفعل، ولا نتخيل انتهاءً من ساعة العميل
  /// عندما يغيب expiresAt من استجابة Fable. لا نعيد إرسال Refresh تلقائياً.
  static DateTime _expiresAt(Object? value,{required String context}) {
    if(value is! String || value.length>64 ||
       !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
       !value.endsWith('Z')) {
      throw FormatException('Missing UTC expiration in $context');
    }
    final time=DateTime.tryParse(value)?.toUtc();
    if(time==null || !time.isAfter(DateTime.now().toUtc())) {
      throw FormatException('Expired or invalid $context');
    }
    return time;
  }

  static bool _requiredPasswordChangeState(Map<String,dynamic> payload) {
    final required=payload['mustChangePassword'];
    if(required is! bool) {
      throw const FormatException('Missing mustChangePassword in Fable login response');
    }
    return required;
  }

  Future<bool> _saveNewSession(Map<String, dynamic> payload, {bool newLogin = false,
      required int expectedIdentity, String? expectedRefreshToken}) async {
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    // فشل التاريخ يمنع حفظ أسرار جلسة منتهية؛ JWT/Session DB يظلان
    // مصدر الصلاحية النهائي، ولا نعد هذا اختباراً لتكامل Backend الحي.
    _expiresAt(payload['expiresAt'],context:'session');
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
    this.methods,this.device,this.expiresAt);
  final String _token;
  final int _identityRevision;
  final List<String> methods;
  /// نحتفظ بنفس بيانات الجهاز للعامل الثاني. لا نخزن Password أو OTP.
  final Map<String,String> device;
  final DateTime expiresAt;
}

/// بيانات تحدي OTP لا تتضمن الرمز نفسه، ونحتفظ بالعنوان المقنّع فقط.
class FableSecondFactorOtpRequest {
  const FableSecondFactorOtpRequest._(this.challengeId,this.method,this.channel,
    this.expiresAt,this.twoFactorExpiresAt,this.maskedDestination);
  final String challengeId,method,channel;
  final DateTime expiresAt,twoFactorExpiresAt;
  final String? maskedDestination;
}

class FableLoginOutcome {
  const FableLoginOutcome._(this.authenticated,this.requiresTwoFactor,
      this.secondFactor,this.mustChangePassword);
  const FableLoginOutcome.authenticated({required bool mustChangePassword}) :
    this._(true,false,null,mustChangePassword);
  const FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge challenge) :
    this._(false,true,challenge,false);
  final bool authenticated;
  final bool requiresTwoFactor;
  final FableSecondFactorChallenge? secondFactor;
  /// Fable يسمح في هذه الحالة فقط بـchange-password/logout حتى نجاح التغيير.
  /// هذا حقل صادر من الخادم، وليس تخميناً من Flutter أو اختياراً في Wizard.
  final bool mustChangePassword;
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
    this.platform,this.clientType,this.appVersion,this.securityState,
  });
  final String id;
  final bool isCurrent;
  final DateTime createdAt,expiresAt;
  final DateTime? lastUsedAt;
  final String? displayName,deviceName,platform,clientType,appVersion;
  /// حالة حماية الجلسة من Backend، وليست حكماً أمنياً محلياً من Flutter.
  final String? securityState;

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
    final security=source['securityState'];
    if(security!=null && (security is! String ||
        !const <String>{'ACTIVE','SUSPICIOUS','COMPROMISED'}.contains(security))) {
      throw const FormatException('Invalid backend session security state');
    }
    return FableActiveSession(
      id:id,isCurrent:source['isCurrent'] as bool,
      createdAt:createdAt,expiresAt:expiresAt,lastUsedAt:lastUsed,
      displayName:optional('displayName',191),
      deviceName:optional('deviceName',191),platform:optional('platform',64),
      clientType:optional('clientType',64),appVersion:optional('appVersion',64),
      securityState:security as String?,
    );
  }
}


/// A confirmed SENSITIVE_ACTION OTP, never serialized or stored in preferences.
/// Backend consumes the challenge on the first protected action if the session
/// itself does not already satisfy the recent AAL2 policy.
class FableVerifiedSensitiveProof {
  const FableVerifiedSensitiveProof._(this._challengeId,this._identityRevision);
  final String _challengeId;
  final int _identityRevision;
}
).hasMatch(code))
      throw ArgumentError('Invalid OTP challenge or code');
    final rev=session.identityRevision;
    final response=await _api.request(_route('/auth/otp/verify','POST'),
      body:{'challengeId':challengeId,'code':code});
    if(session.identityRevision!=rev)throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true || data['challengeId']!=challengeId ||
      data['purpose']!='SENSITIVE_ACTION')
      throw const FormatException('Backend did not verify the expected sensitive-action proof');
    return FableVerifiedSensitiveProof._(challengeId,rev);
  }

  Future<bool> revokeOtherSession(String sessionId,{FableVerifiedSensitiveProof? proof}) async {
    if(!_uuid.hasMatch(sessionId))throw ArgumentError('Invalid session ID');
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(
      _route('/auth/sessions/{id}/revoke','POST'),
      path:{'id':sessionId},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['sessionId']!=sessionId || data['revoked'] is! bool)
      throw const FormatException('Invalid Backend session revocation response');
    // Never silently sign out a different local identity.
    return data['revoked'] as bool;
  }
  bool get canRevokeSelectedSessions => _contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/revoke-selected' && op.method=='POST' &&
      op.requiresAuth && op.credentialHeader==null);

  /// Server-owned bulk revocation. Never loop revoke-one calls (each may
  /// require a distinct consumed step-up proof).
  Future<List<String>> revokeSelectedSessions(List<String> ids,{
    FableVerifiedSensitiveProof? proof,
  })async {
    final selected=ids.toSet().toList(growable:false);
    if(selected.isEmpty||selected.length>100||selected.any((id)=>!_uuid.hasMatch(id)))
      throw ArgumentError('Select 1-100 distinct, valid active session IDs');
    final revision=session.identityRevision;
    if(proof!=null&&proof._identityRevision!=revision)
      throw StateError('Security proof belongs to another identity');
    final response=await _api.request(
      _route('/auth/sessions/revoke-selected','POST'),
      body:{'sessionIds':selected},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    final revoked=data['sessionIds'],current=data['currentSessionRevoked'];
    if(revoked is! List||revoked.any((id)=>id is! String||
        !selected.contains(id)) ||
       revoked.length!=revoked.toSet().length||
       data['revoked'] is! int||data['revoked']!=revoked.length||
       current is! bool)
      throw const FormatException('Backend returned an invalid selected-session revocation');
    if(current)await session.clearSessionIfIdentity(revision);
    return List<String>.unmodifiable(revoked.cast<String>());
  }

  Future<int> revokeAllSessions({FableVerifiedSensitiveProof? proof}) async {
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(_route('/auth/logout-all','POST'),
      securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),count=data['revoked'];
    if(count is! int||count<0)throw const FormatException('Invalid logout-all response');
    await session.clearSessionIfIdentity(rev);
    return count;
  }

  /// Explicit Fable entity-context opt-in for a verified, protected project
  /// operation. Never persist the entity header or propagate it across Backends.
  Future<Response<dynamic>> executeInManagedEntity(String operationId,String managedEntityId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body
  }) {
    if(!_uuid.hasMatch(managedEntityId))throw ArgumentError('Invalid managed entity ID');
    return _api.request(operationId,path:path,query:query,body:body,
      managedEntityId:managedEntityId);
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

  /// يجب رفض اعتماد انتهت مدته بالفعل، ولا نتخيل انتهاءً من ساعة العميل
  /// عندما يغيب expiresAt من استجابة Fable. لا نعيد إرسال Refresh تلقائياً.
  static DateTime _expiresAt(Object? value,{required String context}) {
    if(value is! String || value.length>64 ||
       !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
       !value.endsWith('Z')) {
      throw FormatException('Missing UTC expiration in $context');
    }
    final time=DateTime.tryParse(value)?.toUtc();
    if(time==null || !time.isAfter(DateTime.now().toUtc())) {
      throw FormatException('Expired or invalid $context');
    }
    return time;
  }

  static bool _requiredPasswordChangeState(Map<String,dynamic> payload) {
    final required=payload['mustChangePassword'];
    if(required is! bool) {
      throw const FormatException('Missing mustChangePassword in Fable login response');
    }
    return required;
  }

  Future<bool> _saveNewSession(Map<String, dynamic> payload, {bool newLogin = false,
      required int expectedIdentity, String? expectedRefreshToken}) async {
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    // فشل التاريخ يمنع حفظ أسرار جلسة منتهية؛ JWT/Session DB يظلان
    // مصدر الصلاحية النهائي، ولا نعد هذا اختباراً لتكامل Backend الحي.
    _expiresAt(payload['expiresAt'],context:'session');
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
    this.methods,this.device,this.expiresAt);
  final String _token;
  final int _identityRevision;
  final List<String> methods;
  /// نحتفظ بنفس بيانات الجهاز للعامل الثاني. لا نخزن Password أو OTP.
  final Map<String,String> device;
  final DateTime expiresAt;
}

/// بيانات تحدي OTP لا تتضمن الرمز نفسه، ونحتفظ بالعنوان المقنّع فقط.
class FableSecondFactorOtpRequest {
  const FableSecondFactorOtpRequest._(this.challengeId,this.method,this.channel,
    this.expiresAt,this.twoFactorExpiresAt,this.maskedDestination);
  final String challengeId,method,channel;
  final DateTime expiresAt,twoFactorExpiresAt;
  final String? maskedDestination;
}

class FableLoginOutcome {
  const FableLoginOutcome._(this.authenticated,this.requiresTwoFactor,
      this.secondFactor,this.mustChangePassword);
  const FableLoginOutcome.authenticated({required bool mustChangePassword}) :
    this._(true,false,null,mustChangePassword);
  const FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge challenge) :
    this._(false,true,challenge,false);
  final bool authenticated;
  final bool requiresTwoFactor;
  final FableSecondFactorChallenge? secondFactor;
  /// Fable يسمح في هذه الحالة فقط بـchange-password/logout حتى نجاح التغيير.
  /// هذا حقل صادر من الخادم، وليس تخميناً من Flutter أو اختياراً في Wizard.
  final bool mustChangePassword;
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
    this.platform,this.clientType,this.appVersion,this.securityState,
  });
  final String id;
  final bool isCurrent;
  final DateTime createdAt,expiresAt;
  final DateTime? lastUsedAt;
  final String? displayName,deviceName,platform,clientType,appVersion;
  /// حالة حماية الجلسة من Backend، وليست حكماً أمنياً محلياً من Flutter.
  final String? securityState;

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
    final security=source['securityState'];
    if(security!=null && (security is! String ||
        !const <String>{'ACTIVE','SUSPICIOUS','COMPROMISED'}.contains(security))) {
      throw const FormatException('Invalid backend session security state');
    }
    return FableActiveSession(
      id:id,isCurrent:source['isCurrent'] as bool,
      createdAt:createdAt,expiresAt:expiresAt,lastUsedAt:lastUsed,
      displayName:optional('displayName',191),
      deviceName:optional('deviceName',191),platform:optional('platform',64),
      clientType:optional('clientType',64),appVersion:optional('appVersion',64),
      securityState:security as String?,
    );
  }
}


/// A confirmed SENSITIVE_ACTION OTP, never serialized or stored in preferences.
/// Backend consumes the challenge on the first protected action if the session
/// itself does not already satisfy the recent AAL2 policy.
class FableVerifiedSensitiveProof {
  const FableVerifiedSensitiveProof._(this._challengeId,this._identityRevision);
  final String _challengeId;
  final int _identityRevision;
}
).hasMatch(code)){
      throw ArgumentError('Password reset OTP must be 6-10 digits');
    }
    _requireAuthOperation('auth.otp.public.verify','POST',
      '/auth/otp/public/verify',requiresAuth:false);
    final response=await _api.request('auth.otp.public.verify',
      authorized:false,body:{'challengeId':pending.challengeId,'code':code});
    if(session.identityRevision!=pending._identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true||data['challengeId']!=pending.challengeId||
       data['purpose']!='PASSWORD_RESET'){
      throw const FormatException('Backend OTP verification has wrong purpose or challenge');
    }
    return FablePasswordResetProof._(pending.challengeId,
      pending._identityRevision,this);
  }

  /// Server enforces password policy/history and revokes *all* sessions.
  /// A local gateway must not invent a new session or log/store the password.
  Future<FablePasswordResetResult> completePasswordReset(
      FablePasswordResetProof proof,{required String newPassword}) async {
    if(!identical(proof._owner,this)||
       session.identityRevision!=proof._identityRevision) {
      throw StateError('Reset proof belongs to another Fable identity or gateway');
    }
    if(newPassword.isEmpty||newPassword.length>1024){
      throw ArgumentError('Password reset DTO requires 1-1024 characters');
    }
    _requireAuthOperation('auth.password.reset','POST',
      '/auth/password/reset',requiresAuth:false);
    final response=await _api.request('auth.password.reset',
      authorized:false,body:{
        'challengeId':proof.challengeId,'newPassword':newPassword,
      });
    if(session.identityRevision!=proof._identityRevision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['changed']!=true||data['sessionsRevoked'] is! int||
       (data['sessionsRevoked'] as int)<0 ||
       data['twoFactorPreserved'] is! bool){
      throw const FormatException('Backend did not confirm password reset and session invalidation');
    }
    return FablePasswordResetResult(
      sessionsRevoked:data['sessionsRevoked'] as int,
      twoFactorPreserved:data['twoFactorPreserved'] as bool);
  }

  /// The verified challenge is never a new login, nor a reusable local grant.
  /// It is a short-lived proof consumed atomically by the protected backend operation.
  Future<FableVerifiedSensitiveProof> verifySensitiveActionOtp(String challengeId,String code) async {
    if(!_uuid.hasMatch(challengeId)||!RegExp(r'^[0-9]{4,10}$').hasMatch(code))
      throw ArgumentError('Invalid OTP challenge or code');
    final rev=session.identityRevision;
    final response=await _api.request(_route('/auth/otp/verify','POST'),
      body:{'challengeId':challengeId,'code':code});
    if(session.identityRevision!=rev)throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['verified']!=true || data['challengeId']!=challengeId ||
      data['purpose']!='SENSITIVE_ACTION')
      throw const FormatException('Backend did not verify the expected sensitive-action proof');
    return FableVerifiedSensitiveProof._(challengeId,rev);
  }

  Future<bool> revokeOtherSession(String sessionId,{FableVerifiedSensitiveProof? proof}) async {
    if(!_uuid.hasMatch(sessionId))throw ArgumentError('Invalid session ID');
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(
      _route('/auth/sessions/{id}/revoke','POST'),
      path:{'id':sessionId},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    if(data['sessionId']!=sessionId || data['revoked'] is! bool)
      throw const FormatException('Invalid Backend session revocation response');
    // Never silently sign out a different local identity.
    return data['revoked'] as bool;
  }
  bool get canRevokeSelectedSessions => _contract.operations.values.any(
    (op)=>op.path=='/auth/sessions/revoke-selected' && op.method=='POST' &&
      op.requiresAuth && op.credentialHeader==null);

  /// Server-owned bulk revocation. Never loop revoke-one calls (each may
  /// require a distinct consumed step-up proof).
  Future<List<String>> revokeSelectedSessions(List<String> ids,{
    FableVerifiedSensitiveProof? proof,
  })async {
    final selected=ids.toSet().toList(growable:false);
    if(selected.isEmpty||selected.length>100||selected.any((id)=>!_uuid.hasMatch(id)))
      throw ArgumentError('Select 1-100 distinct, valid active session IDs');
    final revision=session.identityRevision;
    if(proof!=null&&proof._identityRevision!=revision)
      throw StateError('Security proof belongs to another identity');
    final response=await _api.request(
      _route('/auth/sessions/revoke-selected','POST'),
      body:{'sessionIds':selected},securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=revision)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data);
    final revoked=data['sessionIds'],current=data['currentSessionRevoked'];
    if(revoked is! List||revoked.any((id)=>id is! String||
        !selected.contains(id)) ||
       revoked.length!=revoked.toSet().length||
       data['revoked'] is! int||data['revoked']!=revoked.length||
       current is! bool)
      throw const FormatException('Backend returned an invalid selected-session revocation');
    if(current)await session.clearSessionIfIdentity(revision);
    return List<String>.unmodifiable(revoked.cast<String>());
  }

  Future<int> revokeAllSessions({FableVerifiedSensitiveProof? proof}) async {
    final rev=session.identityRevision;
    if(proof!=null && proof._identityRevision!=rev)
      throw StateError('Security proof belongs to another authenticated identity');
    final response=await _api.request(_route('/auth/logout-all','POST'),
      securityChallengeId:proof?._challengeId);
    if(session.identityRevision!=rev)
      throw FableApiException(409,'session_changed_discard_response');
    final data=_payload(response.data),count=data['revoked'];
    if(count is! int||count<0)throw const FormatException('Invalid logout-all response');
    await session.clearSessionIfIdentity(rev);
    return count;
  }

  /// Explicit Fable entity-context opt-in for a verified, protected project
  /// operation. Never persist the entity header or propagate it across Backends.
  Future<Response<dynamic>> executeInManagedEntity(String operationId,String managedEntityId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body
  }) {
    if(!_uuid.hasMatch(managedEntityId))throw ArgumentError('Invalid managed entity ID');
    return _api.request(operationId,path:path,query:query,body:body,
      managedEntityId:managedEntityId);
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

  /// يجب رفض اعتماد انتهت مدته بالفعل، ولا نتخيل انتهاءً من ساعة العميل
  /// عندما يغيب expiresAt من استجابة Fable. لا نعيد إرسال Refresh تلقائياً.
  static DateTime _expiresAt(Object? value,{required String context}) {
    if(value is! String || value.length>64 ||
       !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
       !value.endsWith('Z')) {
      throw FormatException('Missing UTC expiration in $context');
    }
    final time=DateTime.tryParse(value)?.toUtc();
    if(time==null || !time.isAfter(DateTime.now().toUtc())) {
      throw FormatException('Expired or invalid $context');
    }
    return time;
  }

  static bool _requiredPasswordChangeState(Map<String,dynamic> payload) {
    final required=payload['mustChangePassword'];
    if(required is! bool) {
      throw const FormatException('Missing mustChangePassword in Fable login response');
    }
    return required;
  }

  Future<bool> _saveNewSession(Map<String, dynamic> payload, {bool newLogin = false,
      required int expectedIdentity, String? expectedRefreshToken}) async {
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    // فشل التاريخ يمنع حفظ أسرار جلسة منتهية؛ JWT/Session DB يظلان
    // مصدر الصلاحية النهائي، ولا نعد هذا اختباراً لتكامل Backend الحي.
    _expiresAt(payload['expiresAt'],context:'session');
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
    this.methods,this.device,this.expiresAt);
  final String _token;
  final int _identityRevision;
  final List<String> methods;
  /// نحتفظ بنفس بيانات الجهاز للعامل الثاني. لا نخزن Password أو OTP.
  final Map<String,String> device;
  final DateTime expiresAt;
}

/// بيانات تحدي OTP لا تتضمن الرمز نفسه، ونحتفظ بالعنوان المقنّع فقط.
class FableSecondFactorOtpRequest {
  const FableSecondFactorOtpRequest._(this.challengeId,this.method,this.channel,
    this.expiresAt,this.twoFactorExpiresAt,this.maskedDestination);
  final String challengeId,method,channel;
  final DateTime expiresAt,twoFactorExpiresAt;
  final String? maskedDestination;
}

class FableLoginOutcome {
  const FableLoginOutcome._(this.authenticated,this.requiresTwoFactor,
      this.secondFactor,this.mustChangePassword);
  const FableLoginOutcome.authenticated({required bool mustChangePassword}) :
    this._(true,false,null,mustChangePassword);
  const FableLoginOutcome.requiresSecondFactor(FableSecondFactorChallenge challenge) :
    this._(false,true,challenge,false);
  final bool authenticated;
  final bool requiresTwoFactor;
  final FableSecondFactorChallenge? secondFactor;
  /// Fable يسمح في هذه الحالة فقط بـchange-password/logout حتى نجاح التغيير.
  /// هذا حقل صادر من الخادم، وليس تخميناً من Flutter أو اختياراً في Wizard.
  final bool mustChangePassword;
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
    this.platform,this.clientType,this.appVersion,this.securityState,
  });
  final String id;
  final bool isCurrent;
  final DateTime createdAt,expiresAt;
  final DateTime? lastUsedAt;
  final String? displayName,deviceName,platform,clientType,appVersion;
  /// حالة حماية الجلسة من Backend، وليست حكماً أمنياً محلياً من Flutter.
  final String? securityState;

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
    final security=source['securityState'];
    if(security!=null && (security is! String ||
        !const <String>{'ACTIVE','SUSPICIOUS','COMPROMISED'}.contains(security))) {
      throw const FormatException('Invalid backend session security state');
    }
    return FableActiveSession(
      id:id,isCurrent:source['isCurrent'] as bool,
      createdAt:createdAt,expiresAt:expiresAt,lastUsedAt:lastUsed,
      displayName:optional('displayName',191),
      deviceName:optional('deviceName',191),platform:optional('platform',64),
      clientType:optional('clientType',64),appVersion:optional('appVersion',64),
      securityState:security as String?,
    );
  }
}


/// A confirmed SENSITIVE_ACTION OTP, never serialized or stored in preferences.
/// Backend consumes the challenge on the first protected action if the session
/// itself does not already satisfy the recent AAL2 policy.
class FableVerifiedSensitiveProof {
  const FableVerifiedSensitiveProof._(this._challengeId,this._identityRevision);
  final String _challengeId;
  final int _identityRevision;
}


/// A queued public OTP challenge. QUEUED does not guarantee provider delivery.
class FablePasswordResetChallenge {
  const FablePasswordResetChallenge._(
    this.challengeId,this.expiresAt,this._identityRevision,this._owner);
  final String challengeId;
  final DateTime expiresAt;
  final int _identityRevision;
  final FableAuthGateway _owner;
}

/// One-time purpose-confirmed proof; not a bearer token or login session.
class FablePasswordResetProof {
  const FablePasswordResetProof._(
    this.challengeId,this._identityRevision,this._owner);
  final String challengeId;
  final int _identityRevision;
  final FableAuthGateway _owner;
}

/// Server-authoritative reset response; prior sessions are invalidated.
class FablePasswordResetResult {
  const FablePasswordResetResult({
    required this.sessionsRevoked,required this.twoFactorPreserved});
  final int sessionsRevoked;
  final bool twoFactorPreserved;
}
