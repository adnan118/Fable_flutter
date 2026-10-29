import 'package:flutter_test/flutter_test.dart';
import 'package:fable_localization/fable_localization.dart';

void main() {
  test('bundled text remains fallback if optional remote copy misses the key', () {
    final snapshot = FableClientCopySnapshot(
      locale: 'ar', revision: List.filled(64, 'a').join(), entries: const {'welcome': 'أهلًا'},
      checkedAt: DateTime.utc(2026, 10, 29), fromCache: false, offlineFallback: false);
    expect(snapshot.text('welcome', 'Welcome'), 'أهلًا');
    expect(snapshot.text('missing', 'Bundled fallback'), 'Bundled fallback');
  });
}
