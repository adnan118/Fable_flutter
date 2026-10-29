import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fable_core/fable_core.dart';
import 'access_repository.dart';
import 'access_snapshot.dart';

/// Central, account-scoped UI permissions; no permission guards in feature screens.
/// Grants are never persisted and never survive identity replacement/logout.
class FableAccessSession extends ValueNotifier<FableAccessSnapshot?> {
  final FableAccessRepository repository;
  int _epoch = 0;
  String? _sessionId;
  String? _expectedUserId;
  bool _closed = false;
  int? _refreshingEpoch;
  StreamSubscription<FableIdentityEvent>? _identitySubscription;
  StreamSubscription<void>? _denialSubscription;
  FableSecureSession? _credentials;

  FableAccessSession(this.repository) : super(null);

  /// Optional compatibility API for explicitly supplied identities.
  void changeSession(String? sessionId, {String? expectedUserId}) {
    if (_closed) return;
    _epoch++;
    _refreshingEpoch = null; // Old in-flight reads may finish, but cannot block this account.
    _sessionId = sessionId;
    _expectedUserId = expectedUserId;
    value = null;
  }

  /// Bind ONCE to the real credential namespace shared by Auth and API clients.
  /// Works with Fable and explicitly mapped Other Backend Auth gateways.
  Future<void> bindToCredentials(FableSecureSession credentials) async {
    if (_closed) return;
    await _identitySubscription?.cancel();
    await _denialSubscription?.cancel();
    _credentials = credentials;
    changeSession(null);
    _identitySubscription = credentials.identityEvents.listen((event) {
      // Synchronous invalidation before any asynchronous account read.
      changeSession(event.authenticated ? 'identity:${event.revision}' : null);
      if (event.authenticated) unawaited(_refreshIfCurrent(event.revision));
    });
    _denialSubscription = credentials.authorizationDenials.listen((_) {
      if (_sessionId == null) return;
      // 403 can mean policy changed. Never allow a snapshot request that
      // started BEFORE the denial to restore stale permissions. Also do not
      // create a 403 retry storm if the permissions endpoint itself denied us.
      if (_refreshingEpoch == _epoch) {
        _epoch++;
        _refreshingEpoch = null;
        value = null;
        return; // Resume / explicit retry revalidates after this denial.
      }
      value = null;
      unawaited(_refreshIfCurrent(credentials.identityRevision));
    });
    // A saved token is NOT proof of privileges: verify through the protected
    // permissions endpoint. No stale grants are displayed during this request.
    final revision = credentials.identityRevision;
    final token = await credentials.accessToken;
    if (_closed || !identical(_credentials, credentials) ||
        credentials.identityRevision != revision) return;
    if (token == null || token.isEmpty) { changeSession(null); return; }
    changeSession('identity:$revision');
    await _refreshIfCurrent(revision);
  }

  Future<void> _refreshIfCurrent(int revision) async {
    final source = _credentials;
    if (_closed || source == null || source.identityRevision != revision ||
        _sessionId != 'identity:$revision' || _refreshingEpoch == _epoch) return;
    try { await refresh(); } catch (_) { /* fail closed; retry on resume */ }
  }

  /// Call on app foreground/resume or whenever roles change remotely.
  Future<void> onForeground() async {
    final source = _credentials;
    if (source != null) await _refreshIfCurrent(source.identityRevision);
  }

  Future<void> refresh() async {
    if (_closed || _sessionId == null) { if (!_closed) value = null; return; }
    final id = _sessionId;
    final generation = ++_epoch;
    value = null;
    _refreshingEpoch = generation;
    try {
      final next = await repository.current();
      if (_closed || generation != _epoch || _sessionId != id) return;
      if (_expectedUserId != null && next.userId != _expectedUserId) {
        throw StateError('Access snapshot belongs to another account');
      }
      value = next;
    } catch (_) {
      if (!_closed && generation == _epoch) value = null;
      rethrow;
    } finally {
      if (_refreshingEpoch == generation) _refreshingEpoch = null;
    }
  }

  void signOut() => changeSession(null);

  @override
  void dispose() {
    _epoch++; _closed = true;
    unawaited(_identitySubscription?.cancel() ?? Future<void>.value());
    unawaited(_denialSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
