import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_analytics/fable_analytics.dart';

class _ReviewedSink implements FableAnalyticsSink {
  final batches = <List<FableAnalyticsEvent>>[];
  @override
  Future<void> send(List<FableAnalyticsEvent> batch) async {
    batches.add(List.unmodifiable(batch));
  }
}

void main() {
  testWidgets('RC315 consent is off by default and revoked on identity change',
      (tester) async {
    final identity = StreamController<void>.broadcast(sync: true);
    final sink = _ReviewedSink();
    final tracker = FableAnalyticsTracker(sink: sink);
    var revision = 1;
    var eligible = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FableAnalyticsConsentPanel(
          tracker: tracker,
          identityRevision: () => revision,
          identityInvalidations: identity.stream,
          mayCollect: () => eligible,
        ),
      ),
    ));
    expect(tracker.hasConsent, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(tracker.hasConsent, isTrue);
    tracker.record(FableAnalyticsEvent.create('screen_view', {'screen': 'home'}));
    expect(tracker.pendingCount, 1);
    revision = 2;
    identity.add(null);
    await tester.pump();
    expect(tracker.hasConsent, isFalse);
    expect(tracker.pendingCount, 0);
    expect(sink.batches, isEmpty);
    eligible = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FableAnalyticsConsentPanel(
          tracker: tracker,
          identityRevision: () => revision,
          identityInvalidations: identity.stream,
          mayCollect: () => eligible,
        ),
      ),
    ));
    expect(tracker.hasConsent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await identity.close();
    tracker.dispose();
  });

  testWidgets('RC315 changing tracker revokes old and new consent',
      (tester) async {
    final identity = StreamController<void>.broadcast(sync: true);
    final a = FableAnalyticsTracker(sink: _ReviewedSink());
    final b = FableAnalyticsTracker(sink: _ReviewedSink(), consent: true);
    var active = a;
    Widget panel() => MaterialApp(home: Scaffold(body:
      FableAnalyticsConsentPanel(
        tracker: active,
        identityRevision: () => 1,
        identityInvalidations: identity.stream,
        mayCollect: () => true,
      ),
    ));
    await tester.pumpWidget(panel());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(a.hasConsent, isTrue);
    active = b;
    await tester.pumpWidget(panel());
    expect(a.hasConsent, isFalse);
    expect(b.hasConsent, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await identity.close();
    a.dispose();
    b.dispose();
  });
}
