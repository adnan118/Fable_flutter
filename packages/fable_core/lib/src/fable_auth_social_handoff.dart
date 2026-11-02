part of 'fable_auth_gateway.dart';

/// RC95: Consume only the server-issued social first-factor challenge.
/// This converts no OTP into authentication; it only permits the standard
/// pending 2FA request/complete flow to verify the actual second factor.
extension FableSocialSecondFactorHandoff on FableAuthGateway {
  FableSecondFactorChallenge adoptSocialSecondFactor({
    required Map<String,dynamic> challengeData,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) {
    _requireAuthOperation('auth.2fa.login.request','POST',
      '/auth/2fa/login/request',requiresAuth:false);
    _requireAuthOperation('auth.2fa.login.complete','POST',
      '/auth/2fa/login/complete',requiresAuth:false);
    final value=challengeData['twoFactorToken'];
    final methods=challengeData['methods'];
    final expires=challengeData['expiresAt'];
    if(value is! String || value.length<32 || value.length>512 ||
      methods is! List || methods.isEmpty || methods.length>2 ||
      methods.any((x)=>x is! String ||
        !const {'EMAIL_OTP','PHONE_OTP'}.contains(x)) ||
      methods.toSet().length!=methods.length) {
      throw const FormatException('Invalid social 2FA handoff');
    }
    final until=FableAuthGateway._expiresAt(expires,context:'social 2FA');
    final device=FableAuthGateway._validatedDeviceMetadata(
      platform:platform,deviceName:deviceName,appVersion:appVersion);
    return FableSecondFactorChallenge._(value,session.identityRevision,
      List<String>.unmodifiable(methods.cast<String>()),device,until);
  }
}
