import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

void main() {
  test('Cloudflare signed URL requires HTTPS + R2 domain + signed request', () {
    final valid = Uri.parse('https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc');
    expect(() => CloudflareR2PartTransport.validatePresignedUri(valid), returnsNormally);
    for (final url in <String>[
      'https://evil.example.com/upload?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc',
      'http://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc',
      'https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/bucket/key',
      'https://user:password@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/bucket/key?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc',
    ]) {
      expect(() => CloudflareR2PartTransport.validatePresignedUri(Uri.parse(url)), throwsStateError);
    }
  });
}
