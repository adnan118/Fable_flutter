part of 'fable_auth_gateway.dart';

extension FableVerifiedContactSecurity on FableAuthGateway {
  bool get canChangeEmailWithOtp => canRequestAuthenticatedOtp &&
    _supportsAuthOperation('auth.contact.email.change','POST',
      '/auth/contact/email/change',requiresAuth:true);
  bool get canChangePhoneWithOtp => canRequestAuthenticatedOtp &&
    _supportsAuthOperation('auth.contact.phone.change','POST',
      '/auth/contact/phone/change',requiresAuth:true);

  Future<FableContactChange> changeVerifiedContact(
    FableVerifiedSecurityOtp proof,{
    required String newDestination,
    FableVerifiedSensitiveProof? securityProof,
  }) async {
    final purpose=proof.purpose;
    if(purpose==FableSecurityOtpPurpose.twoFactor) {
      throw StateError('A destination OTP proof is required');
    }
    _validateVerifiedSecurityOtp(this,proof,purpose);
    _validateRecentAuthProof(this,securityProof,proof._identityRevision);
    final email=purpose==FableSecurityOtpPurpose.changeEmail;
    final destination=email?newDestination.trim().toLowerCase():
      newDestination.trim();
    if(destination!=proof._destination||proof._destination==null||
       email&&!_validSecurityEmail(destination)||
       !email&&!_securityPhoneE164.hasMatch(destination)) {
      throw ArgumentError('Contact does not match verified destination');
    }
    if(proof._inFlight)throw StateError('Contact change is already in progress');
    final op=email?'auth.contact.email.change':'auth.contact.phone.change';
    _requireAuthOperation(op,'POST',email?'/auth/contact/email/change':
      '/auth/contact/phone/change',requiresAuth:true);
    proof._inFlight=true;
    try {
      final response=await _api.request(op,body:{
        'challengeId':proof.challengeId,
        if(email)'newEmail':destination,
        if(!email)'newPhone':destination,
        if(securityProof!=null)
          'securityChallengeId':securityProof._challengeId,
      });
      if(session.identityRevision!=proof._identityRevision) {
        throw FableApiException(409,'session_changed_discard_response');
      }
      final data=FableAuthGateway._payload(response.data);
      if(data['changed']!=true||data['verified']!=true||
         data['revokedOtherSessions'] is! int||
         (data['revokedOtherSessions'] as int)<0) {
        throw const FormatException('Backend did not confirm contact change');
      }
      proof._consumed=true;
      return FableContactChange._(
        purpose,data['revokedOtherSessions'] as int);
    } finally {
      proof._inFlight=false;
    }
  }
}
