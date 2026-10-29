import 'package:fable_core/fable_core.dart';

/// Passkeys are WebAuthn public-key credentials, not raw fingerprints or Face ID.
/// Flutter NEVER receives or sends raw biometric material to Backend.
abstract interface class FablePasskeyAuthenticator {
  /// Implement with an audited Android Credential Manager / iOS
  /// AuthenticationServices plugin. Must bind RP ID and server challenge.
  Future<Map<String, dynamic>?> getAssertion(Map<String, dynamic> publicKeyOptions);
}

class FablePasskeyOperations {
  const FablePasskeyOperations._(this.optionsId,this.verifyId);
  final String optionsId,verifyId;
  factory FablePasskeyOperations.fromContract(OperationCatalog catalog,
      {required String optionsId,required String verifyId}) {
    final options = catalog.require(optionsId), verify = catalog.require(verifyId);
    if (options.method != 'POST' || verify.method != 'POST' ||
        options.requiresAuth || verify.requiresAuth || options.credentialHeader != null ||
        verify.credentialHeader != null || options.path.contains('{') ||
        verify.path.contains('{') || options.path.contains(':') || verify.path.contains(':')) {
      throw const FormatException('Passkey login requires public POST options and verify');
    }
    return FablePasskeyOperations._(options.id,verify.id);
  }
  factory FablePasskeyOperations.fable(OperationCatalog catalog) =>
      FablePasskeyOperations.fromContract(catalog,
        optionsId:'passkeys.authentication.options',verifyId:'passkeys.authentication.verify');
}

typedef FablePasskeyOptionsDecoder = Map<String, dynamic> Function(Object? response);
typedef FablePasskeyVerifyDecoder = Object? Function(Object? response);

class FablePasskeyRepository {
  const FablePasskeyRepository({required this.gateway,required this.operations,
      required this.authenticator,required this.session,required this.decodeOptions,
      required this.decodeVerify});
  final BackendApiGateway gateway;
  final FablePasskeyOperations operations;
  final FablePasskeyAuthenticator authenticator;
  final FableSecureSession session;
  final FablePasskeyOptionsDecoder decodeOptions;
  final FablePasskeyVerifyDecoder decodeVerify;
  /// Runs only from explicit user interaction. The verified response is passed
  /// to the existing Auth coordinator (including 2FA), not stored automatically.
  Future<Object?> authenticate({String? identifier}) async {
    if (identifier != null && (identifier.length > 255 || identifier.trim().isEmpty)) {
      throw ArgumentError('Invalid passkey identifier');
    }
    final identity = session.identityRevision;
    final optionsResult = await gateway.execute(operations.optionsId,
      body:{if(identifier!=null)'identifier':identifier});
    if (session.identityRevision != identity) return null;
    final options = FableImmutablePayload.object(decodeOptions(optionsResult.data));
    final challengeId = options['challengeId'];
    final publicKey = options['options'];
    if (challengeId is! String || challengeId.length < 8 || challengeId.length > 128 ||
        publicKey is! Map<String, dynamic> || publicKey['challenge'] is! String ||
        (publicKey['challenge'] as String).length < 16 ||
        publicKey['rpId'] is! String || (publicKey['rpId'] as String).isEmpty) {
      throw const FormatException('Passkey challenge not bound to a verified RP');
    }
    final assertion = await authenticator.getAssertion(publicKey);
    if (assertion == null || session.identityRevision != identity) return null;
    final safe = FableImmutablePayload.object(assertion);
    if (safe['id'] is! String || safe['response'] is! Map ||
        (safe['response'] as Map)['clientDataJSON'] is! String ||
        (safe['response'] as Map)['authenticatorData'] is! String ||
        (safe['response'] as Map)['signature'] is! String) {
      throw const FormatException('Invalid WebAuthn assertion');
    }
    final verified = await gateway.execute(operations.verifyId,
      body:{'challengeId':challengeId,'response':safe,'clientType':'flutter'});
    // Backend verifies challenge, origin, RP, signature and counter.
    if (session.identityRevision != identity) return null;
    return decodeVerify(verified.data);
  }
}
