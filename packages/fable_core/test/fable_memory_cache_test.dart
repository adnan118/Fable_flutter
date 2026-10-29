import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  test('concurrent public reads share one in-flight request', () async {
    final cache = FableMemoryCache(maximumEntries: 3);
    final pending = Completer<String>();
    var requests = 0;
    Future<String> fetch() { requests++; return pending.future; }
    final first = cache.load<String>('public.catalog', fetch: fetch);
    final second = cache.load<String>('public.catalog', fetch: fetch);
    expect(requests, 1);
    pending.complete('ready');
    expect(await Future.wait([first, second]), ['ready', 'ready']);
    expect(cache.peek<String>('public.catalog'), 'ready');
  });

  test('stale-while-revalidate gives cached data without waiting for network', () async {
    final cache = FableMemoryCache();
    await cache.load<String>('public.feed', fetch: () async => 'old', ttl: Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final pending = Completer<String>();
    var requests = 0;
    final result = await cache.load<String>('public.feed', fetch: () {
      requests++;
      return pending.future;
    });
    expect(result, 'old');
    expect(requests, 1);
    pending.complete('new');
    await Future<void>.delayed(Duration.zero);
    // An awaited non-stale read is guaranteed to observe the refresh.
    expect(await cache.load<String>('public.feed', fetch: () async => 'unwanted', allowStale: false), 'new');
  });

  test('clearing a cache invalidates outstanding requests and prevents stale repopulation', () async {
    final cache = FableMemoryCache();
    final pending = Completer<String>();
    final prior = cache.load<String>('public.news', fetch: () => pending.future);
    cache.clear();
    expect(await cache.load<String>('public.news', fetch: () async => 'new'), 'new');
    pending.complete('old');
    expect(await prior, 'old'); // Original waiter still receives its completion.
    expect(cache.peek<String>('public.news'), 'new'); // Cache never regresses.
  });

  test('removal prevents an obsolete background refresh from restoring a key', () async {
    final cache = FableMemoryCache();
    final pending = Completer<String>();
    final old = cache.load<String>('public.news', fetch: () => pending.future);
    cache.remove('public.news');
    pending.complete('outdated');
    await old;
    expect(cache.peek<String>('public.news'), isNull);
  });

  test('bounded cache evicts the least recently used entry', () async {
    final cache = FableMemoryCache(maximumEntries: 2);
    await cache.load<String>('one', fetch: () async => '1');
    await cache.load<String>('two', fetch: () async => '2');
    expect(cache.peek<String>('one'), '1'); // Mark one as recently used.
    await cache.load<String>('three', fetch: () async => '3');
    expect(cache.peek<String>('one'), '1');
    expect(cache.peek<String>('two'), isNull);
    expect(cache.peek<String>('three'), '3');
  });
}
