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
  FableManagedEntityStore? _managedEntityStore;
  int _managedSelectionRevision = 0;

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
  Future<void> bindToCredentials(FableSecureSession credentials, {
    FableManagedEntityStore? managedEntityStore,
  }) async {
    if (_closed) return;
    if (managedEntityStore != null &&
        (!managedEntityStore.bound ||
         !managedEntityStore.isBoundToCredentials(credentials))) {
      throw StateError('Managed entity context must share the authenticated Backend identity namespace');
    }
    _managedEntityStore?.removeListener(_onManagedSelectionChanged);
    await _identitySubscription?.cancel();
    await _denialSubscription?.cancel();
    _credentials = credentials;
    _managedEntityStore = managedEntityStore;
    _managedSelectionRevision = managedEntityStore?.selectionRevision ?? 0;
    managedEntityStore?.addListener(_onManagedSelectionChanged);
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

  /// A managed-account switch invalidates the current UI snapshot immediately.
  /// The permissions endpoint remains user-global: managed roles are a separate
  /// Backend context and are never converted into global permission keys here.
  void _onManagedSelectionChanged() {
    final store = _managedEntityStore;
    if (_closed || store == null) return;
    final selectionRevision = store.selectionRevision;
    if (selectionRevision == _managedSelectionRevision) return;
    _managedSelectionRevision = selectionRevision;
    final source = _credentials;
    _epoch++;
    _refreshingEpoch = null;
    value = null;
    if (source != null &&
        _sessionId == 'identity:${source.identityRevision}') {
      unawaited(_refreshIfCurrent(source.identityRevision));
    }
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
    final credentials = _credentials;
    final identityAtStart = credentials?.identityRevision;
    final generation = ++_epoch;
    value = null;
    _refreshingEpoch = generation;
    try {
      final next = await repository.current();
      // The secure-session epoch can advance without a matching UI stream
      // callback (for example, during storage errors or a client swap).
      // Never grant old-account permissions on that stale response.
      if (_closed || generation != _epoch || _sessionId != id ||
          !identical(_credentials, credentials) ||
          (credentials != null &&
           (credentials.identityRevision != identityAtStart ||
            id != 'identity:$identityAtStart'))) return;
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
    _managedEntityStore?.removeListener(_onManagedSelectionChanged);
    _managedEntityStore = null;
    unawaited(_identitySubscription?.cancel() ?? Future<void>.value());
    unawaited(_denialSubscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
