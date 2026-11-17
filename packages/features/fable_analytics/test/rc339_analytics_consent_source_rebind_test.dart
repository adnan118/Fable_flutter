import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_analytics/fable_analytics.dart';

class _DiscardSink implements FableAnalyticsSink {
  final batches = <List<FableAnalyticsEvent>>[];
  @override
  Future<void> send(List<FableAnalyticsEvent> batch) async {
    batches.add(List.unmodifiable(batch));
  }
}

void main() {
  testWidgets('RC339 a new identity callback revokes consent even when numeric revision is equal',
      (tester) async {
    final events = StreamController<void>.broadcast(sync: true);
    final sink = _DiscardSink();
    final tracker = FableAnalyticsTracker(sink: sink);
    final first = () => 1;
    final second = () => 1;
    final allowed = () => true;
    int Function() revision = first;
    Widget panel() => MaterialApp(home: Scaffold(body:
      FableAnalyticsConsentPanel(
        tracker: tracker,
        identityRevision: revision,
        identityInvalidations: events.stream,
        mayCollect: allowed,
      ),
    ));
    await tester.pumpWidget(panel());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(tracker.hasConsent, isTrue);
    tracker.record(FableAnalyticsEvent.create('screen_view', {'screen': 'home'}));
    expect(tracker.pendingCount, 1);
    revision = second;
    await tester.pumpWidget(panel());
    expect(tracker.hasConsent, isFalse);
    expect(tracker.pendingCount, 0);
    expect(sink.batches, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
    tracker.dispose();
  });

  testWidgets('RC339 replacement eligibility predicate revokes even when both return true',
      (tester) async {
    final events = StreamController<void>.broadcast(sync: true);
    final tracker = FableAnalyticsTracker(sink: _DiscardSink());
    final first = () => true;
    final second = () => true;
    bool Function() policy = first;
    final revision = () => 5;
    Widget panel() => MaterialApp(home: Scaffold(body:
      FableAnalyticsConsentPanel(
        tracker: tracker,
        identityRevision: revision,
        identityInvalidations: events.stream,
        mayCollect: policy,
      ),
    ));
    await tester.pumpWidget(panel());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(tracker.hasConsent, isTrue);
    policy = second;
    await tester.pumpWidget(panel());
    expect(tracker.hasConsent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
    tracker.dispose();
  });
}
