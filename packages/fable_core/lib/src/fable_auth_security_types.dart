part of 'fable_auth_gateway.dart';

/// Exact purpose from Backend's RequestOtpDto; no implicit purpose coercion.
enum FableSecurityOtpPurpose {
  twoFactor('TWO_FACTOR'),
  changeEmail('CHANGE_EMAIL'),
  changePhone('CHANGE_PHONE');
  const FableSecurityOtpPurpose(this.backendPurpose);
  final String backendPurpose;
}

class FableTwoFactorStatus {
  const FableTwoFactorStatus._(this.enabled,this.enabledAt,this.methods);
  final bool enabled;
  final DateTime? enabledAt;
  final List<String> methods;
}

class FableSecurityOtpChallenge {
  const FableSecurityOtpChallenge._(
    this.challengeId,this.expiresAt,this.purpose,this._destination,
    this._identityRevision,this._owner);
  final String challengeId;
  final DateTime expiresAt;
  final FableSecurityOtpPurpose purpose;
  final String? _destination;
  final int _identityRevision;
  final FableAuthGateway _owner;
}

class FableVerifiedSecurityOtp {
  FableVerifiedSecurityOtp._(
    this.challengeId,this.purpose,this._destination,this._identityRevision,
    this._owner);
  final String challengeId;
  final FableSecurityOtpPurpose purpose;
  final String? _destination;
  final int _identityRevision;
  final FableAuthGateway _owner;
  bool _consumed=false;
  bool _inFlight=false;
}

class FableTwoFactorUpdate {
  const FableTwoFactorUpdate._(this.enabled,this.revokedOtherSessions);
  final bool enabled;
  final int revokedOtherSessions;
}

class FableContactChange {
  const FableContactChange._(this.purpose,this.revokedOtherSessions);
  final FableSecurityOtpPurpose purpose;
  final int revokedOtherSessions;
}

final _securityPhoneE164=RegExp(r'^\+[1-9]\d{6,14}$');
bool _validSecurityEmail(String email)=>
  email.isNotEmpty&&email.length<=191&&
  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

void _validateVerifiedSecurityOtp(FableAuthGateway gateway,
    FableVerifiedSecurityOtp proof,FableSecurityOtpPurpose purpose) {
  if(!identical(proof._owner,gateway)||proof.purpose!=purpose||
     proof._consumed||gateway.session.identityRevision!=proof._identityRevision) {
    throw StateError('Security proof belongs to another identity/purpose or is consumed');
  }
}

void _validateRecentAuthProof(FableAuthGateway gateway,
    FableVerifiedSensitiveProof? securityProof,int revision) {
  if(securityProof!=null &&
     (!identical(securityProof._owner,gateway)||
      securityProof._identityRevision!=revision)) {
    throw StateError('Recent-auth proof belongs to another session or gateway');
  }
}
