import 'package:fable_core/fable_core.dart';

/// Native WebAuthn registration must use Credential Manager/AuthenticationServices.
/// No fingerprint, Face ID image or private key is returned to Flutter.
abstract interface class FablePasskeyCreator {
  Future<Map<String,dynamic>?> createCredential(Map<String,dynamic> publicKeyOptions);
}

/// Only Fable's signed project contract may enable the Fable registration flow.
/// The registration verification route contains the server-generated challengeId.
class FablePasskeyRegistrationOperations {
  const FablePasskeyRegistrationOperations._(this.optionsId,this.verifyId);
  final String optionsId,verifyId;

  factory FablePasskeyRegistrationOperations.fable(FableContract contract) {
    const optionsId='passkeys.registration.options';
    const verifyId='passkeys.registration.verify';
    final options=contract.require(optionsId);
    final verify=contract.require(verifyId);
    if(options.method!='POST'||verify.method!='POST'||
        options.path!='/auth/passkeys/registration/options'||
        !const <String>{
          '/auth/passkeys/registration/:challengeId/verify',
          '/auth/passkeys/registration/{challengeId}/verify'
        }.contains(verify.path)||
        !options.requiresAuth||!verify.requiresAuth||
        !options.enforceAuth||!verify.enforceAuth||
        options.credentialHeader!=null||verify.credentialHeader!=null||
        options.contractHash.isEmpty||verify.contractHash.isEmpty) {
      throw const FormatException('Passkey registration requires protected verified Fable operations');
    }
    return const FablePasskeyRegistrationOperations._(optionsId,verifyId);
  }
}

typedef FablePasskeyRegistrationDecoder = Map<String,dynamic> Function(Object? response);

/// User-initiated enrolment, bound to one secure-session identity and the
/// backend's one-time challenge. Step-up proof is validated by Backend.
class FablePasskeyRegistrationRepository {
  FablePasskeyRegistrationRepository({required this.gateway,required this.operations,
    required this.creator,required this.session,required this.decodeOptions,
    required this.decodeVerify});
  final BackendApiGateway gateway;
  final FablePasskeyRegistrationOperations operations;
  final FablePasskeyCreator creator;
  final FableSecureSession session;
  final FablePasskeyRegistrationDecoder decodeOptions,decodeVerify;
  static final _uuid=RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    caseSensitive:false);
  bool _working=false;

  Future<bool> register({String? label,String? securityChallengeId}) async {
    if(_working)throw StateError('Passkey registration is already in progress');
    if(label!=null && (label.trim().isEmpty||label.length>191||
        label.contains(RegExp(r'[\x00-\x1f\x7f]')))){
      throw ArgumentError('Invalid passkey label');
    }
    if(securityChallengeId!=null&&!_uuid.hasMatch(securityChallengeId)){
      throw ArgumentError('Invalid step-up challenge');
    }
    _working=true;
    try{
      final identity=session.identityRevision;
      final token=await session.accessToken;
      if(token==null||token.isEmpty||session.identityRevision!=identity){
        throw StateError('Authenticated session is required to register passkeys');
      }
      final issued=await gateway.execute(operations.optionsId);
      if(session.identityRevision!=identity)return false;
      final options=FableImmutablePayload.object(decodeOptions(issued.data));
      final challengeId=options['challengeId'],publicKey=options['options'];
      if(challengeId is! String||!_uuid.hasMatch(challengeId)||
          publicKey is! Map<String,dynamic>||
          publicKey['challenge'] is! String||
          (publicKey['challenge'] as String).length<16||
          publicKey['rp'] is! Map||
          (publicKey['rp'] as Map)['id'] is! String||
          ((publicKey['rp'] as Map)['id'] as String).isEmpty) {
        throw const FormatException('Unverified passkey enrolment challenge');
      }
      final credential=await creator.createCredential(publicKey);
      if(credential==null||session.identityRevision!=identity)return false;
      final safe=FableImmutablePayload.object(credential);
      final response=safe['response'];
      if(safe['id'] is! String||(safe['id'] as String).isEmpty||
          safe['rawId'] is! String||safe['type']!='public-key'||
          response is! Map||
          response['clientDataJSON'] is! String||
          response['attestationObject'] is! String||
          (response['clientDataJSON'] as String).length<16||
          (response['attestationObject'] as String).length<16) {
        throw const FormatException('Invalid native WebAuthn registration credential');
      }
      final verified=await gateway.execute(operations.verifyId,
        path:{'challengeId':challengeId},
        body:{
          'response':safe,
          if(label!=null)'label':label.trim(),
          if(securityChallengeId!=null)'securityChallengeId':securityChallengeId,
        });
      if(session.identityRevision!=identity)return false;
      final body=FableImmutablePayload.object(decodeVerify(verified.data));
      return body['verified']==true;
    }finally{_working=false;}
  }
}
