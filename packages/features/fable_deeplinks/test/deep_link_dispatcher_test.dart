import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_deeplinks/fable_deeplinks.dart';

void main() {
  test('late authorization for older links cannot open or replace newer link', () async {
    final router = FableDeepLinkDispatcher.instance;
    router.clearPending();
    final older = Completer<bool>();
    final newer = Completer<bool>();
    final visited = <String>[];
    router.register('/test-link', (uri) async {
      visited.add(uri.path);
      return true;
    });
    router.authorization = (uri) => uri.path.endsWith('/old')
        ? older.future : newer.future;
    try {
      final stale = router.dispatch(Uri.parse('https://example.com/test-link/old'));
      final current = router.dispatch(Uri.parse('https://example.com/test-link/new'));
      newer.complete(false);
      expect(await current, isFalse);
      older.complete(true);
      expect(await stale, isFalse);
      expect(visited, isEmpty);
      // Re-check current link when session changes, never trust old grants.
      router.authorization = (_) async => true;
      expect(await router.resumeAfterLogin(), isTrue);
      expect(visited, ['/test-link/new']);
    } finally {
      router.clearPending();
      router.authorization = null;
      router.unregister('/test-link');
    }
  });
}
