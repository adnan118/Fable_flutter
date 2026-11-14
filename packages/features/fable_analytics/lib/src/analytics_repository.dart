import 'dart:async';
import 'dart:collection';

/// Privacy-first, opt-in client analytics. Not a substitute for an authorized
/// backend collection API and NOT wired to external endpoints implicitly.
class FableAnalyticsEvent {
  FableAnalyticsEvent._(this.name, this.at, this.attributes);
  final String name;
  final DateTime at;
  final Map<String, String> attributes;
  factory FableAnalyticsEvent.create(String name, Map<String, String> attributes,
      {DateTime? at}) {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{1,79}$').hasMatch(name) || attributes.length > 12) {
      throw ArgumentError('Invalid analytics event name/attributes');
    }
    final safe = <String,String>{};
    for (final entry in attributes.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(entry.key) ||
          !const {'screen','action','category','result','source','variant','platform'}.contains(entry.key) ||
          entry.value.length > 80 ||
          entry.value.contains(RegExp(r'[@:/\\]|[0-9]{7,}|[\x00-\x1f]'))) {
        throw ArgumentError('Disallowed potentially identifying analytics attribute');
      }
      safe[entry.key] = entry.value;
    }
    return FableAnalyticsEvent._(name,(at??DateTime.now()).toUtc(),Map.unmodifiable(safe));
  }
}

abstract interface class FableAnalyticsSink {
  /// A project-provided reviewed sink; analytics never chooses an endpoint.
  Future<void> send(List<FableAnalyticsEvent> batch);
}

class FableAnalyticsTracker {
  FableAnalyticsTracker({
    required FableAnalyticsSink sink,
    bool consent = false,
    Stream<void>? identityInvalidations,
  }) : _sink = sink, _consent = consent {
    // Consent belongs to a user/session. A different identity must opt in
    // separately, even if the host reuses the same tracker instance.
    _identitySubscription = identityInvalidations?.listen((_) => setConsent(false));
  }
  final FableAnalyticsSink _sink;
  StreamSubscription<void>? _identitySubscription;
  bool _consent;
  bool _sending = false;
  bool _disposed = false;
  int _consentRevision = 0;
  final Queue<FableAnalyticsEvent> _queue = Queue();

  bool get hasConsent => !_disposed && _consent;
  int get pendingCount => _queue.length;

  void setConsent(bool value) {
    if (_disposed) {
      if (value) throw StateError('Disposed analytics tracker cannot resume');
      return;
    }
    if (_consent != value) _consentRevision++;
    _consent = value;
    if (!value) _queue.clear(); // Revoke all unsent events immediately.
  }

  void record(FableAnalyticsEvent event) {
    if (!hasConsent) return;
    if (_queue.length >= 100) _queue.removeFirst();
    _queue.addLast(event);
  }

  Future<void> flush() async {
    if (!hasConsent || _sending || _queue.isEmpty) return;
    _sending = true;
    final revision = _consentRevision;
    final batch = List<FableAnalyticsEvent>.unmodifiable(_queue);
    try {
      // This sink call may already be in flight when consent is withdrawn;
      // only the sink/provider can cancel a sent request. We never allow its
      // completion to delete events recorded under a NEW consent revision.
      await _sink.send(batch);
      if (hasConsent && revision == _consentRevision) {
        for (final delivered in batch) { _queue.remove(delivered); }
      }
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _consent = false;
    _consentRevision++;
    _queue.clear();
    unawaited(_identitySubscription?.cancel());
    _identitySubscription = null;
  }
}
