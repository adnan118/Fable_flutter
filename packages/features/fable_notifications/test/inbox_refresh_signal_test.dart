import 'package:flutter_test/flutter_test.dart';
import 'package:fable_notifications/fable_notifications.dart';

void main() {
  test('inbox refresh signals broadcast to all active subscribers', () async {
    var first = 0;
    var second = 0;
    final a = FableInboxRefreshSignal.instance.changes.listen((_) => first++);
    final b = FableInboxRefreshSignal.instance.changes.listen((_) => second++);
    try {
      FableInboxRefreshSignal.instance.notifyChanged();
      expect(first, 1);
      expect(second, 1);
    } finally {
      await a.cancel();
      await b.cancel();
    }
  });
}
