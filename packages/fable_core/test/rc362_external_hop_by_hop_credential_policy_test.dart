import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  test('RC362 external credentials cannot override hop-by-hop HTTP framing or authentication challenges', () {
    for (final header in <String>[
      'TE', 'Trailer', 'Upgrade', 'Keep-Alive', 'Proxy-Connection',
      'Proxy-Authenticate', 'WWW-Authenticate', 'Via',
      'tE', 'proxy-connection',
    ]) {
      expect(isAllowedExternalCredentialHeader(header), isFalse, reason: header);
    }
  });

  test('RC362 legitimate external credential headers remain allowed', () {
    for (final header in <String>['Authorization', 'X-API-Key', 'X-Client-Key']) {
      expect(isAllowedExternalCredentialHeader(header), isTrue, reason: header);
    }
  });
}
