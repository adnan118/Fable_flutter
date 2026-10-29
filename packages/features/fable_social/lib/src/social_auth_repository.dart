import 'package:fable_core/fable_core.dart';

/// Social authentication never collects passwords, stores identity tokens, or
/// launches an arbitrary URL. A platform-specific, vetted identity SDK supplies
/// a signed credential for the nonce supplied by the chosen backend.
enum FableSocialProvider { google, apple }

extension FableSocialProviderName on FableSocialProvider {
  String get wireName => name;
}

class FableSocialChallenge {
  const FableSocialChallenge({required this.provider, required this.state,
    required this.nonce, required this.expiresInMs});
  final FableSocialProvider provider;
  final String state, nonce;
  final int expiresInMs;
  static FableSocialChallenge fromFable(Object? payload, FableSocialProvider provider) {
    final obj = FableSocialAdapter.unwrap(payload);
    final state = obj['state'], nonce = obj['nonce'], expires = obj['expiresInMs'];
    if (obj['provider'] != provider.wireName || state is! String || nonce is! String ||
        state.length < 20 || nonce.length < 20 || state.length > 512 || nonce.length > 512 ||
        expires is! int || expires < 1000 || expires > 3600000) {
      throw const FormatException('Invalid social challenge from backend');
    }
    return FableSocialChallenge(provider: provider, state: state,
      nonce: nonce, expiresInMs: expires);
  }
}

/// Token fields are transient and must never be logged, cached, or rendered.
class FableSocialCredential {
  const FableSocialCredential({required this.provider, required this.nonce,
    required this.identityToken, this.authorizationCode, this.givenName,
    this.familyName});
  final FableSocialProvider provider;
  final String nonce, identityToken;
  final String? authorizationCode, givenName, familyName;
}

/// Provided by the host app's approved Google/Apple native identity SDK.
/// The SDK must validate its configured audience and use challenge.nonce.
abstract interface class FableSocialCredentialProvider {
  Future<FableSocialCredential?> obtain(FableSocialChallenge challenge);
}

/// Other Backend must supply a reviewed mapping/codec, never inherit Fable JSON.
abstract interface class FableSocialAdapter {
  Map<String, dynamic> challengeRequest(FableSocialProvider provider);
  FableSocialChallenge parseChallenge(Object? response, FableSocialProvider provider);
  Map<String, dynamic> credentialRequest(FableSocialCredential credential, FableSocialChallenge challenge,
    {String? securityChallengeId});
  Object? parseAuthResponse(Object? response);

  static Map<String, dynamic> unwrap(Object? value) {
    final candidate = value is Map && value['data'] is Map ? value['data'] : value;
    if (candidate is! Map) throw const FormatException('Invalid social response');
    return Map<String, dynamic>.from(candidate);
  }
}

class FableSocialBackendAdapter implements FableSocialAdapter {
  const FableSocialBackendAdapter();
  @override Map<String, dynamic> challengeRequest(FableSocialProvider provider) =>
    {'provider': provider.wireName};
  @override FableSocialChallenge parseChallenge(Object? response, FableSocialProvider provider) =>
    FableSocialChallenge.fromFable(response, provider);
  @override Map<String, dynamic> credentialRequest(FableSocialCredential credential,
      FableSocialChallenge challenge, {String? securityChallengeId}) {
    final token = credential.identityToken;
    if (token.length < 20 || token.length > 12000 || token.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        credential.provider != challenge.provider || credential.nonce != challenge.nonce ||
        (credential.provider == FableSocialProvider.apple &&
          (credential.authorizationCode == null || credential.authorizationCode!.length < 6))) {
      throw const FormatException('Invalid provider credential');
    }
    return {
      if (credential.provider == FableSocialProvider.google) 'idToken': token,
      if (credential.provider == FableSocialProvider.apple) ...{
        'identityToken': token,
        'authorizationCode': credential.authorizationCode,
        if (credential.givenName != null) 'givenName': credential.givenName,
        if (credential.familyName != null) 'familyName': credential.familyName,
      },
      'state': challenge.state, 'nonce': challenge.nonce, 'clientType': 'flutter',
      if (securityChallengeId != null) 'securityChallengeId': securityChallengeId,
    };
  }
  @override Object? parseAuthResponse(Object? response) => FableSocialAdapter.unwrap(response);
}

/// Operation IDs are pinned to the imported backend contract, not URL strings.
class FableSocialOperations {
  FableSocialOperations._(this.ids);
  final Map<String, String> ids;
  static const fableIds = <String, String>{
    'challenge':'auth.social.challenge',
    'google':'auth.social.google',
    'apple':'auth.social.apple',
    'googleLink':'auth.social.google.link',
    'appleLink':'auth.social.apple.link',
    'unlink':'auth.social.unlink',
  };
  static const _authorized = {'googleLink','appleLink','unlink'};
  factory FableSocialOperations.fable(FableContract catalog) =>
    FableSocialOperations._checked(catalog, fableIds);
  factory FableSocialOperations.external(ExternalOperationCatalog catalog,
      Map<String, String> bindings) => FableSocialOperations._checked(catalog, bindings);
  factory FableSocialOperations._checked(OperationCatalog catalog, Map<String, String> bindings) {
    if (!bindings.containsKey('challenge') ||
        !bindings.containsKey('google') && !bindings.containsKey('apple')) {
      throw const FormatException('Missing social challenge or sign-in operation');
    }
    final result = <String, String>{};
    for (final binding in bindings.entries) {
      if (!fableIds.containsKey(binding.key)) throw const FormatException('Unknown social operation role');
      final op = catalog.require(binding.value);
      final expected = binding.key == 'unlink' ? 'DELETE' : 'POST';
      if (op.method != expected || op.requiresAuth != _authorized.contains(binding.key) ||
          op.credentialHeader != null || op.path.contains('?') || op.path.contains('#') ||
          (!op.path.startsWith('/')) ||
          (binding.key != 'unlink' && (op.path.contains('{') || op.path.contains(':'))) ||
          (binding.key == 'unlink' && !op.path.contains('{provider}'))) {
        throw const FormatException('Unsafe social contract binding');
      }
      result[binding.key] = op.id;
    }
    return FableSocialOperations._(Map.unmodifiable(result));
  }
  bool supports(String role) => ids.containsKey(role);
  String require(String role) => ids[role] ?? (throw StateError('Social operation not bound: $role'));
}

class FableSocialAuthResult {
  const FableSocialAuthResult({required this.signedIn, required this.requiresTwoFactor,
    this.challengeData});
  final bool signedIn, requiresTwoFactor;
  /// Hand off to the existing Auth 2FA flow; no session is created yet.
  final Map<String, dynamic>? challengeData;
}

/// The Auth gateway and this repository MUST use the same secure-session namespace.
/// Login commits are identity-epoch checked: a late OAuth result cannot undo logout.
class FableSocialRepository {
  const FableSocialRepository({required this.gateway, required this.operations,
    required this.session, required this.credentials, required this.adapter});
  final BackendApiGateway gateway;
  final FableSocialOperations operations;
  final FableSecureSession session;
  final FableSocialCredentialProvider credentials;
  final FableSocialAdapter adapter;

  Future<FableSocialAuthResult?> signIn(FableSocialProvider provider) => _run(provider, link: false);
  Future<bool?> link(FableSocialProvider provider, {required String securityChallengeId}) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(securityChallengeId)) {
      throw ArgumentError('Recent authentication proof required');
    }
    final outcome = await _run(provider, link: true, securityChallengeId: securityChallengeId);
    return outcome == null ? null : outcome.signedIn;
  }
  Future<FableSocialAuthResult?> _run(FableSocialProvider provider,
      {required bool link, String? securityChallengeId}) async {
    final identity = session.identityRevision;
    if (link && await session.accessToken == null) throw StateError('Sign in before linking social identity');
    final challengeResponse = await gateway.execute(operations.require('challenge'),
      body: adapter.challengeRequest(provider));
    if (session.identityRevision != identity) return null;
    final challenge = adapter.parseChallenge(challengeResponse.data, provider);
    final started = DateTime.now().toUtc();
    final credential = await credentials.obtain(challenge);
    if (credential == null || session.identityRevision != identity) return null;
    if (DateTime.now().toUtc().difference(started).inMilliseconds >= challenge.expiresInMs) {
      throw StateError('Social challenge expired');
    }
    if (credential.provider != provider || credential.nonce != challenge.nonce) {
      throw const FormatException('Provider credential challenge mismatch');
    }
    final role = link ? '${provider.wireName}Link' : provider.wireName;
    final response = await gateway.execute(operations.require(role),
      body: adapter.credentialRequest(credential, challenge, securityChallengeId: securityChallengeId));
    if (session.identityRevision != identity) return null;
    final payload = adapter.parseAuthResponse(response.data);
    if (payload is! Map) throw const FormatException('Malformed social auth response');
    if (link) {
      if (payload['linked'] != true || payload['provider'] != provider.wireName) {
        throw const FormatException('Link not confirmed by backend');
      }
      return const FableSocialAuthResult(signedIn: true, requiresTwoFactor: false);
    }
    if (payload['requiresTwoFactor'] == true) {
      // A second factor does not grant an authenticated session.
      if (payload['twoFactorToken'] is! String ||
          (payload['twoFactorToken'] as String).length < 32 ||
          (payload['twoFactorToken'] as String).length > 512) {
        throw const FormatException('Invalid second-factor challenge');
      }
      return FableSocialAuthResult(signedIn:false, requiresTwoFactor:true,
        challengeData: FableImmutablePayload.object({
          'twoFactorToken':payload['twoFactorToken'],
          if (payload['methods'] is List) 'methods':payload['methods'],
        }));
    }
    final access = payload['accessToken'], refresh = payload['refreshToken'];
    if (access is! String || access.isEmpty || access.length > 8192 ||
        access.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        refresh is! String || !RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(refresh)) {
      throw const FormatException('Invalid social session tokens');
    }
    final saved = await session.replaceTokensIfIdentity(expectedIdentity: identity,
      accessToken: access, refreshToken: refresh);
    if (!saved) return null;
    return const FableSocialAuthResult(signedIn:true, requiresTwoFactor:false);
  }

}
