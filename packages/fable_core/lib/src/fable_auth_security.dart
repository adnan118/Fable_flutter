part of 'fable_auth_gateway.dart';

/// Source-verified Fable OTP and two-factor flow. No guessed routes or
/// promotion to an authenticated login session after OTP verification.
extension FableAccountSecurity on FableAuthGateway {
  bool get canReadTwoFactorStatus => _supportsAuthOperation(
    'auth.2fa.status','GET','/auth/2fa/status',requiresAuth:true);

  bool get canManageTwoFactor => canReadTwoFactorStatus &&
    _supportsAuthOperation('auth.2fa.enable','POST','/auth/2fa/enable',
      requiresAuth:true) &&
    _supportsAuthOperation('auth.2fa.disable','POST','/auth/2fa/disable',
      requiresAuth:true) &&
    _supportsAuthOperation('auth.otp.request','POST','/auth/otp/request',
      requiresAuth:true) &&
    _supportsAuthOperation('auth.otp.verify','POST','/auth/otp/verify',
      requiresAuth:true);

  bool get canRequestAuthenticatedOtp =>
    _supportsAuthOperation('auth.otp.request','POST','/auth/otp/request',
      requiresAuth:true) &&
    _supportsAuthOperation('auth.otp.verify','POST','/auth/otp/verify',
      requiresAuth:true);

  Future<FableTwoFactorStatus> loadTwoFactorStatus() async {
    _requireAuthOperation('auth.2fa.status','GET','/auth/2fa/status',
      requiresAuth:true);
    final revision=session.identityRevision;
    final response=await _api.request('auth.2fa.status');
    if(session.identityRevision!=revision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=FableAuthGateway._payload(response.data);
    final enabled=data['enabled'],methods=data['methods'],
      timestamp=data['enabledAt'];
    if(enabled is! bool||methods is! List||methods.length>2||
       methods.any((v)=>v is! String||
         !const {'EMAIL_OTP','PHONE_OTP'}.contains(v))||
       methods.toSet().length!=methods.length||
       timestamp!=null&&timestamp is! String) {
      throw const FormatException('Invalid two-factor status response');
    }
    final enabledAt=timestamp is String?DateTime.tryParse(timestamp)?.toUtc():null;
    if(timestamp!=null&&enabledAt==null) {
      throw const FormatException('Invalid two-factor enabledAt');
    }
    return FableTwoFactorStatus._(enabled,enabledAt,
      List<String>.unmodifiable(methods.cast<String>()));
  }

  /// A contact change challenge must go to the NEW destination.
  /// A normal TWO_FACTOR challenge uses an already-verified account channel.
  Future<FableSecurityOtpChallenge> requestSecurityOtp({
    required FableSecurityOtpPurpose purpose,
    String? newDestination,
    String? preferredChannel,
  }) async {
    if(!canRequestAuthenticatedOtp) {
      throw StateError('Fable authenticated OTP operations were not exported');
    }
    final destination=newDestination?.trim();
    if(purpose==FableSecurityOtpPurpose.twoFactor) {
      if(destination!=null||
          preferredChannel!=null&&
          !const {'EMAIL','PHONE'}.contains(preferredChannel)) {
        throw ArgumentError('TWO_FACTOR requires verified account contact');
      }
    } else if(purpose==FableSecurityOtpPurpose.changeEmail) {
      if(destination==null||!_validSecurityEmail(destination)||
         preferredChannel!=null&&preferredChannel!='EMAIL') {
        throw ArgumentError('CHANGE_EMAIL needs a new email address');
      }
    } else if(destination==null||!_securityPhoneE164.hasMatch(destination)||
       preferredChannel!=null&&preferredChannel!='PHONE') {
      throw ArgumentError('CHANGE_PHONE needs a new E.164 phone');
    }

    final target=purpose==FableSecurityOtpPurpose.changeEmail
      ?destination!.toLowerCase():destination;
    final revision=session.identityRevision;
    final response=await _api.request('auth.otp.request',body:{
      'purpose':purpose.backendPurpose,
      if(target!=null)'destination':target,
      if(preferredChannel!=null)'preferredChannel':preferredChannel,
    });
    if(session.identityRevision!=revision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final body=FableAuthGateway._payload(response.data),id=body['challengeId'];
    if(id is! String||!FableAuthGateway._uuid.hasMatch(id)||
       !const {'EMAIL','PHONE'}.contains(body['channel'])||
       body['transport'] is! String||body['destination'] is! String) {
      throw const FormatException('Backend returned an invalid OTP challenge');
    }
    if(purpose==FableSecurityOtpPurpose.changeEmail&&body['channel']!='EMAIL'||
       purpose==FableSecurityOtpPurpose.changePhone&&body['channel']!='PHONE') {
      throw const FormatException('OTP challenge destination channel mismatched');
    }
    return FableSecurityOtpChallenge._(id,
      FableAuthGateway._expiresAt(body['expiresAt'],context:'security OTP'),
      purpose,target,revision,this);
  }

  Future<FableVerifiedSecurityOtp> verifySecurityOtp(
      FableSecurityOtpChallenge pending,String code) async {
    if(!identical(pending._owner,this)||
       session.identityRevision!=pending._identityRevision||
       !pending.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('OTP challenge expired or belongs to another identity');
    }
    if(!RegExp(r'^[0-9]{6,10}$').hasMatch(code)) {
      throw ArgumentError('Fable VerifyOtpDto requires 6 to 10 digits');
    }
    _requireAuthOperation('auth.otp.verify','POST','/auth/otp/verify',
      requiresAuth:true);
    final response=await _api.request('auth.otp.verify',body:{
      'challengeId':pending.challengeId,'code':code,
    });
    if(session.identityRevision!=pending._identityRevision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=FableAuthGateway._payload(response.data);
    if(data['verified']!=true||data['challengeId']!=pending.challengeId||
       data['purpose']!=pending.purpose.backendPurpose) {
      throw const FormatException('OTP verification purpose/challenge mismatch');
    }
    return FableVerifiedSecurityOtp._(pending.challengeId,pending.purpose,
      pending._destination,pending._identityRevision,this);
  }

  Future<FableTwoFactorUpdate> setTwoFactorEnabled(
      FableVerifiedSecurityOtp proof,{required bool enabled}) async {
    _validateVerifiedSecurityOtp(this,proof,FableSecurityOtpPurpose.twoFactor);
    if(proof._inFlight)throw StateError('OTP is already being used');
    final op=enabled?'auth.2fa.enable':'auth.2fa.disable',
      path=enabled?'/auth/2fa/enable':'/auth/2fa/disable';
    _requireAuthOperation(op,'POST',path,requiresAuth:true);
    proof._inFlight=true;
    try {
      final response=await _api.request(op,body:{'challengeId':proof.challengeId});
      if(session.identityRevision!=proof._identityRevision) {
        throw FableApiException(409,'session_changed_discard_response');
      }
      final body=FableAuthGateway._payload(response.data),
        revoked=body['revokedOtherSessions'];
      if(body['enabled']!=enabled||revoked is! int||revoked<0||
         enabled&&(body['enabledAt'] is! String||
           DateTime.tryParse(body['enabledAt'])==null)) {
        throw const FormatException('Backend did not confirm the 2FA state');
      }
      proof._consumed=true;
      return FableTwoFactorUpdate._(enabled,revoked);
    } finally {
      proof._inFlight=false;
    }
  }
}
