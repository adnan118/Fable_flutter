import 'dart:async';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sensitive state stays in OS backed storage, never shared preferences or assets.
/// Non-secret, process-local identity signals shared by adapters using one session namespace.
/// Login, account replacement and logout publish only after secure storage commits.
class FableIdentityEvent {
  const FableIdentityEvent(this.revision, this.authenticated);
  final int revision;
  final bool authenticated;
}

class FableSecureSession {
  FableSecureSession({FlutterSecureStorage? storage, String namespace = 'fable'}) :
      _prefix = _validateNamespace(namespace), _storage = storage ?? const FlutterSecureStorage();
  // Process-local, namespace-scoped identity epoch shared by clients using
  // the same secure-session namespace. Refresh rotation does NOT change it;
  // login/account replacement and logout do. Never persisted as a secret.
  static String _validateNamespace(String value) {
    if (!RegExp(r'^[a-z0-9._-]{1,96}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'namespace', 'Invalid secure session namespace');
    }
    return value;
  }
  static final Map<String, int> _identityEpochs = <String, int>{};
  static final StreamController<String> _denials =
      StreamController<String>.broadcast(sync: true);
  Stream<void> get authorizationDenials => _denials.stream
      .where((namespace) => namespace == _prefix).map((_) {});
  void reportAuthorizationDenied() => _denials.add(_prefix);
  static final StreamController<_ScopedIdentityEvent> _events =
      StreamController<_ScopedIdentityEvent>.broadcast(sync: true);
  Stream<FableIdentityEvent> get identityEvents => _events.stream
      .where((event) => event.namespace == _prefix)
      .map((event) => event.change);
  void _publishIdentity(bool authenticated) => _events.add(_ScopedIdentityEvent(
      _prefix, FableIdentityEvent(identityRevision, authenticated)));

  static Future<String>? _installationIdInFlight;
  static final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};
  int get identityRevision => _identityEpochs[_prefix] ?? 0;
  void _advanceIdentity() {
    _identityEpochs[_prefix] = identityRevision + 1;
  }
  Future<void> _serializedWrite(Future<void> Function() operation) async {
    final previous = _pendingWrites[_prefix];
    final next = Completer<void>();
    final marker = next.future;
    _pendingWrites[_prefix] = marker;
    try {
      if (previous != null) await previous;
      await operation();
    } finally {
      if (identical(_pendingWrites[_prefix], marker)) {
        _pendingWrites.remove(_prefix);
      }
      next.complete(); // Never poison the queue when a native write fails.
    }
  }
  final String _prefix;
  final FlutterSecureStorage _storage;
  String get _idKey => 'fable.installation.id';
  String get _accessKey => '$_prefix.session.access';
  String get _refreshKey => '$_prefix.session.refresh';
  Future<String> installationId() async {
    final previous = _installationIdInFlight;
    if (previous != null) return previous;
    final creation = _readOrCreateInstallationId();
    _installationIdInFlight = creation;
    try { return await creation; }
    finally { if (identical(_installationIdInFlight, creation)) _installationIdInFlight = null; }
  }
  Future<String> _readOrCreateInstallationId() async {
    final old = await _storage.read(key:_idKey);
    if (old != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(old)) return old;
    final random=Random.secure();
    final id=List<int>.generate(16, (_) => random.nextInt(256)).map((n)=>n.toRadixString(16).padLeft(2,'0')).join();
    await _storage.write(key:_idKey,value:id);
    return id;
  }
  // A login/refresh writes more than one secure-storage key. Readers must
  // wait for the namespace write queue to drain, never observe a half-written
  // access/refresh pair during account switching.
  Future<String?> get accessToken async {
    final pending = _pendingWrites[_prefix];
    if (pending != null) await pending;
    return _storage.read(key:_accessKey);
  }
  Future<String?> get refreshToken async {
    final pending = _pendingWrites[_prefix];
    if (pending != null) await pending;
    return _storage.read(key:_refreshKey);
  }
  /// Commit refreshed credentials only when they still belong to the same
  /// signed-in identity. The check is INSIDE the namespace write lock.
  Future<bool> saveTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken,
      String? expectedRefreshToken}) async {
    var committed = false;
    await _serializedWrite(() async {
      if (identityRevision != expectedIdentity) return;
      if (expectedRefreshToken != null &&
          await _storage.read(key:_refreshKey) != expectedRefreshToken) return;
      await _storage.write(key:_accessKey,value:accessToken);
      if (refreshToken != null) await _storage.write(key:_refreshKey,value:refreshToken);
      committed = true;
    });
    return committed;
  }

  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    await saveTokensIfIdentity(expectedIdentity: identityRevision,
      accessToken: accessToken, refreshToken: refreshToken);
  }

  /// A login response that arrived after another login/logout must not
  /// replace the newer identity. Distinct calls have distinct epochs.
  Future<bool> replaceTokensIfIdentity({required int expectedIdentity,
      required String accessToken, String? refreshToken}) async {
    var committed = false;
    await _serializedWrite(() async {
      if (identityRevision != expectedIdentity) return;
      _advanceIdentity();
      await _storage.write(key:_accessKey,value:accessToken);
      if (refreshToken == null) await _storage.delete(key:_refreshKey);
      else await _storage.write(key:_refreshKey,value:refreshToken);
      committed = true;
      _publishIdentity(true);
    });
    return committed;
  }

  Future<void> replaceTokens({required String accessToken, String? refreshToken}) async {
    await replaceTokensIfIdentity(expectedIdentity: identityRevision,
      accessToken: accessToken, refreshToken: refreshToken);
  }

  /// Atomic identity+credential compare-and-clear. Defeats stale 401,
  /// late logout and late refresh failures even during an in-flight login.
  Future<bool> clearSessionIfIdentity(int expectedIdentity, {String? expectedAccessToken,
      String? expectedRefreshToken}) async {
    var cleared = false;
    await _serializedWrite(() async {
      if (identityRevision != expectedIdentity) return;
      if (expectedAccessToken != null &&
          await _storage.read(key:_accessKey) != expectedAccessToken) return;
      if (expectedRefreshToken != null &&
          await _storage.read(key:_refreshKey) != expectedRefreshToken) return;
      _advanceIdentity();
      await _storage.delete(key:_accessKey);
      await _storage.delete(key:_refreshKey);
      cleared = true;
      _publishIdentity(false);
    });
    return cleared;
  }

  Future<void> clearSession() async {
    await clearSessionIfIdentity(identityRevision);
  }
}

class _ScopedIdentityEvent {
  const _ScopedIdentityEvent(this.namespace, this.change);
  final String namespace;
  final FableIdentityEvent change;
}
