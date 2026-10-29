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
  FableAnalyticsTracker({required FableAnalyticsSink sink, bool consent = false})
      : _sink = sink, _consent = consent;
  final FableAnalyticsSink _sink;
  bool _consent;
  final Queue<FableAnalyticsEvent> _queue = Queue();
  bool _sending = false;
  bool get hasConsent => _consent;
  int get pendingCount => _queue.length;
  void setConsent(bool value) {
    _consent = value;
    if (!value) _queue.clear(); // revoke immediately; never persisted
  }
  void record(FableAnalyticsEvent event) {
    if (!_consent) return;
    if (_queue.length >= 100) _queue.removeFirst();
    _queue.addLast(event);
  }
  Future<void> flush() async {
    if (!_consent || _sending || _queue.isEmpty) return;
    _sending = true;
    final batch = List<FableAnalyticsEvent>.unmodifiable(_queue);
    try {
      await _sink.send(batch);
      if (_consent) {
        for (final delivered in batch) { _queue.remove(delivered); }
      }
    } finally { _sending = false; }
  }
  void dispose() { _consent = false; _queue.clear(); }
}
