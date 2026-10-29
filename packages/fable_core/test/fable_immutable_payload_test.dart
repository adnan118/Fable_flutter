import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  test('preserves all fields without allowing nested mutation', () {
    final original = {'user': {'name': 'A', 'unknown': [1, {'enabled': true}]}, 'version': 12};
    final snapshot = FableImmutablePayload.object(original);
    expect(snapshot, original);
    (original['user'] as Map)['name'] = 'changed';
    expect(snapshot['user']['name'], 'A');
    expect(() => snapshot['version'] = 13, throwsUnsupportedError);
    expect(() => snapshot['user']['unknown'].add(2), throwsUnsupportedError);
  });
  test('invalid / excessively deep response fails, never truncates fields', () {
    expect(() => FableImmutablePayload.object({'x': DateTime(2026)}), throwsFormatException);
    expect(() => FableImmutablePayload.object({'x': double.nan}), throwsFormatException);
    Object data = 'leaf';
    for (var i = 0; i < 30; i++) { data = {'item': data}; }
    expect(() => FableImmutablePayload.object(data), throwsFormatException);
  });
}
