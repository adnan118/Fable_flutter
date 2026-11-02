part of 'fable_auth_gateway.dart';

/// RC95: Public LOGIN OTP is not interchangeable with reset, contact or 2FA.
/// Backend RC66 owns delivery, proof consumption and second-factor policy.
extension FablePublicOtpLogin on FableAuthGateway {
  bool get canLoginWithPublicOtp =>
    _supportsAuthOperation('auth.otp.public.request', 'POST',
      '/auth/otp/public/request', requiresAuth:false) &&
    _supportsAuthOperation('auth.otp.public.verify', 'POST',
      '/auth/otp/public/verify', requiresAuth:false) &&
    _supportsAuthOperation('auth.otp.login.complete', 'POST',
      '/auth/otp/login/complete', requiresAuth:false);

  Future<FableOtpLoginChallenge> requestLoginOtp({
    required String identifier, String? preferredChannel,
  }) async {
    if (!canLoginWithPublicOtp) throw StateError('OTP login is not present in verified Fable contract');
    final value=identifier.trim();
    if(value.isEmpty || value.length>191 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
        preferredChannel!=null && !const {'EMAIL','PHONE'}.contains(preferredChannel)) {
      throw ArgumentError('Invalid OTP login request');
    }
    final epoch=session.identityRevision;
    final response=await _api.request('auth.otp.public.request',authorized:false,body:{
      'purpose':'LOGIN','identifier':value,
      if(preferredChannel!=null)'preferredChannel':preferredChannel,
    });
    if(session.identityRevision!=epoch) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=FableAuthGateway._payload(response.data),id=data['challengeId'];
    if(data['accepted']!=true||data['deliveryStatus']!='QUEUED' ||
        id is! String || !FableAuthGateway._uuid.hasMatch(id)) {
      throw const FormatException('Backend did not acknowledge LOGIN OTP request');
    }
    return FableOtpLoginChallenge._(id,
      FableAuthGateway._expiresAt(data['expiresAt'],context:'LOGIN OTP'),
      epoch,this);
  }

  Future<FableVerifiedLoginOtp> verifyLoginOtp(
      FableOtpLoginChallenge pending,String code) async {
    if (!identical(pending._owner,this) ||
        session.identityRevision!=pending._identityRevision ||
        !pending.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('Expired LOGIN OTP or changed identity');
    }
    if(!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      throw ArgumentError('Invalid Fable LOGIN OTP');
    }
    _requireAuthOperation('auth.otp.public.verify','POST',
      '/auth/otp/public/verify',requiresAuth:false);
    final response=await _api.request('auth.otp.public.verify',
      authorized:false,body:{'challengeId':pending.challengeId,'code':code});
    if(session.identityRevision!=pending._identityRevision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=FableAuthGateway._payload(response.data);
    if(data['verified']!=true || data['purpose']!='LOGIN' ||
        data['challengeId']!=pending.challengeId) {
      throw const FormatException('OTP verification has a different purpose');
    }
    return FableVerifiedLoginOtp._(
      pending.challengeId,pending._identityRevision,this);
  }

  /// Returns a session only on an explicit Backend confirmation.
  /// OTP is never reused as a second factor and does not bypass enabled 2FA.
  Future<FableLoginOutcome> completeLoginWithOtp(
    FableVerifiedLoginOtp proof,{required String platform,
      String? deviceName,String? appVersion}) async {
    if(!identical(proof._owner,this) ||
        session.identityRevision!=proof._identityRevision ||
        proof._submitted) {
      throw StateError('LOGIN proof is invalid, submitted or belongs to another user');
    }
    _requireAuthOperation('auth.otp.login.complete','POST',
      '/auth/otp/login/complete',requiresAuth:false);
    final device=FableAuthGateway._validatedDeviceMetadata(platform:platform,
      deviceName:deviceName,appVersion:appVersion);
    // One-shot even if HTTP times out: avoid replaying a potentially consumed proof.
    proof._submitted=true;
    final response=await _api.request('auth.otp.login.complete',authorized:false,body:{
      'challengeId':proof.challengeId,
      'clientType':'flutter',
      'installationId':await session.installationId(),
      ...device,
    });
    if(session.identityRevision!=proof._identityRevision) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    final data=FableAuthGateway._payload(response.data);
    final mandatory=FableAuthGateway._requiredPasswordChangeState(data);
    final saved=await _saveNewSession(data,newLogin:true,
      expectedIdentity:proof._identityRevision);
    if(!saved) {
      throw FableApiException(409,'session_changed_discard_response');
    }
    return FableLoginOutcome.authenticated(mustChangePassword:mandatory);
  }
}

class FableOtpLoginChallenge {
  const FableOtpLoginChallenge._(this.challengeId,this.expiresAt,
    this._identityRevision,this._owner);
  final String challengeId;
  final DateTime expiresAt;
  final int _identityRevision;
  final FableAuthGateway _owner;
}
class FableVerifiedLoginOtp {
  FableVerifiedLoginOtp._(this.challengeId,this._identityRevision,this._owner);
  final String challengeId;
  final int _identityRevision;
  final FableAuthGateway _owner;
  bool _submitted=false;
}
