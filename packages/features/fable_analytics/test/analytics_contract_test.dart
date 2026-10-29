import 'package:flutter_test/flutter_test.dart';
import 'package:fable_analytics/fable_analytics.dart';

class Sink implements FableAnalyticsSink {
  final sent=<FableAnalyticsEvent>[];
  @override Future<void> send(List<FableAnalyticsEvent> batch) async {sent.addAll(batch);}
}
void main(){
  test('no analytics without opt-in; revoke clears unsent events',() async {
    final sink=Sink(), tracker=FableAnalyticsTracker(sink:sink);
    final e=FableAnalyticsEvent.create('screen_view',{'screen':'home'});
    tracker.record(e);expect(tracker.pendingCount,0);
    tracker.setConsent(true);tracker.record(e);expect(tracker.pendingCount,1);
    tracker.setConsent(false);expect(tracker.pendingCount,0);
    await tracker.flush();expect(sink.sent,isEmpty);
    tracker.setConsent(true);tracker.record(e);await tracker.flush();expect(sink.sent.length,1);
  });
  test('rejects PII-like attributes and arbitrary keys',(){
    expect(()=>FableAnalyticsEvent.create('tap',{'email':'person@example.com'}),throwsArgumentError);
    expect(()=>FableAnalyticsEvent.create('tap',{'source':'person@example.com'}),throwsArgumentError);
  });
}
