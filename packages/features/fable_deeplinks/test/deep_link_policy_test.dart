import 'package:flutter_test/flutter_test.dart';
import 'package:fable_deeplinks/fable_deeplinks.dart';
void main(){
  const policy = FableDeepLinkPolicy(host:'example.com',paths:['/content','/profile']);
  test('accepts HTTPS and exact boundaries',(){
    expect(policy.accepts(Uri.parse('https://example.com/content/42')),isTrue);
    expect(policy.accepts(Uri.parse('https://example.com/content')),isTrue);
    expect(policy.accepts(Uri.parse('https://example.com/contents')),isFalse);
    expect(policy.accepts(Uri.parse('http://example.com/content/42')),isFalse);
    expect(policy.accepts(Uri.parse('https://fake.example.com/content/42')),isFalse);
    expect(policy.accepts(Uri.parse('https://example.com:444/content/42')),isFalse);
    expect(policy.accepts(Uri.parse('https://x@example.com/content/42')),isFalse);
    expect(policy.accepts(Uri.parse('https://example.com/admin/42')),isFalse);
    expect(policy.accepts(Uri.parse('https://example.com/content/%2e%2e/secret')),isFalse);
    expect(policy.accepts(Uri.parse('https://example.com/content/%2fsecret')),isFalse);
  });
  test('rejects unsafe configuration and label boundaries',(){
    expect(() => FableDeepLinkPolicy.fromJson('{"domain":"bad-.example.com","paths":["/content"]}'), throwsFormatException);
    expect(() => FableDeepLinkPolicy.fromJson('{"domain":"example.com","paths":["/content/%2e%2e/admin"]}'), throwsFormatException);
  });
}
