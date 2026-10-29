import 'dart:async';

/// Process-local, payload-free invalidation for an open notification inbox.
/// Incoming Firebase foreground messages do not grant navigation or access.
class FableInboxRefreshSignal {
  FableInboxRefreshSignal._();
  static final instance = FableInboxRefreshSignal._();
  final StreamController<int> _changes = StreamController<int>.broadcast(sync: true);
  int _revision = 0;
  Stream<int> get changes => _changes.stream;
  void notifyChanged() => _changes.add(++_revision);
}
