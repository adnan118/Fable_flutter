part of 'fable_auth_gateway.dart';

/// RC94: Username is a public handle, not an authentication identifier or
/// proof of account ownership. The backend remains authoritative for uniqueness.
extension FableUsernameOperations on FableAuthGateway {
  bool get canCheckUsernameAvailability => _supportsAuthOperation(
    'auth.username.availability', 'GET',
    '/auth/me/username/availability/:username', requiresAuth: true);

  bool get canUpdateUsername => _supportsAuthOperation(
    'auth.username.update', 'PATCH', '/auth/me/username',
    requiresAuth: true);

  static final RegExp _usernameFormat =
      RegExp(r'^[a-z0-9](?:[a-z0-9._]{1,28}[a-z0-9])?$');
  static const Set<String> _reserved = {
    'admin', 'administrator', 'api', 'app', 'auth', 'billing',
    'fable', 'help', 'login', 'logout', 'me', 'moderator', 'null',
    'official', 'root', 'security', 'staff', 'support', 'system',
    'undefined', 'user', 'users', 'webmaster',
  };

  String _validateUsername(String input) {
    // Do not silently canonicalize manual updates: the server enforces
    // its own policy, including uniqueness and recovery reservations.
    if (input.length < 3 || input.length > 30 ||
        !_usernameFormat.hasMatch(input) || _reserved.contains(input)) {
      throw ArgumentError.value(input, 'username', 'Invalid Fable username');
    }
    return input;
  }

  Future<FableUsernameAvailability> checkUsernameAvailability(
      String username) async {
    _requireAuthOperation('auth.username.availability', 'GET',
      '/auth/me/username/availability/:username', requiresAuth: true);
    final value = _validateUsername(username);
    final revision = session.identityRevision;
    final response = await _api.request(
      'auth.username.availability', path: {'username': value});
    if (session.identityRevision != revision) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    final payload = FableAuthGateway._payload(response.data);
    if (payload['username'] != value || payload['available'] is! bool) {
      throw const FormatException('Unexpected username availability response');
    }
    return FableUsernameAvailability(value, payload['available'] as bool);
  }

  Future<FableUsernameUpdate> updateUsername(String username,
      {String? securityChallengeId}) async {
    _requireAuthOperation('auth.username.update', 'PATCH',
      '/auth/me/username', requiresAuth: true);
    final value = _validateUsername(username);
    if (securityChallengeId != null &&
        !FableAuthGateway._uuid.hasMatch(securityChallengeId)) {
      throw ArgumentError('Invalid recent-auth proof identifier');
    }
    final revision = session.identityRevision;
    final response = await _api.request('auth.username.update', body: {
      'username': value,
      if (securityChallengeId != null)
        'securityChallengeId': securityChallengeId,
    });
    if (session.identityRevision != revision) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    final payload = FableAuthGateway._payload(response.data);
    if (payload['username'] != value || payload['changed'] is! bool) {
      throw const FormatException('Backend did not confirm username result');
    }
    return FableUsernameUpdate(value, payload['changed'] as bool);
  }
}

extension FableSocialUnlinkSecurity on FableAuthGateway {
  bool get canUnlinkSocialIdentity => _supportsAuthOperation(
    'auth.social.unlink', 'DELETE', '/auth/social/:provider',
    requiresAuth: true);

  /// Only a verified, server-supplied recent-auth proof may authorize unlink.
  /// Backend will reject removal of the final remaining sign-in method.
  Future<FableSocialUnlinkOutcome> unlinkSocialIdentity(String provider,
      {required String securityChallengeId}) async {
    _requireAuthOperation('auth.social.unlink', 'DELETE',
      '/auth/social/:provider', requiresAuth: true);
    if (!const {'google','apple'}.contains(provider)) {
      throw ArgumentError('Unsupported social identity provider');
    }
    if (!FableAuthGateway._uuid.hasMatch(securityChallengeId)) {
      throw ArgumentError('Invalid recent-auth proof identifier');
    }
    final revision = session.identityRevision;
    final response = await _api.request('auth.social.unlink',
      path: {'provider':provider}, securityChallengeId:securityChallengeId);
    if (session.identityRevision != revision) {
      throw FableApiException(409, 'session_changed_discard_response');
    }
    final data = FableAuthGateway._payload(response.data);
    if (data['provider'] != provider || data['unlinked'] is! bool ||
        !const {'none','transactional-outbox'}.contains(data['externalCleanup'])) {
      throw const FormatException('Backend did not confirm unlink result');
    }
    return FableSocialUnlinkOutcome(provider,
      data['unlinked'] as bool, data['externalCleanup'] as String);
  }
}
class FableSocialUnlinkOutcome {
  const FableSocialUnlinkOutcome(this.provider,this.unlinked,this.externalCleanup);
  final String provider;
  final bool unlinked;
  final String externalCleanup;
}

class FableUsernameAvailability {
  const FableUsernameAvailability(this.username, this.available);
  final String username;
  final bool available;
}

class FableUsernameUpdate {
  const FableUsernameUpdate(this.username, this.changed);
  final String username;
  final bool changed;
}
