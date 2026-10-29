import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  test('Only safe reads are eligible for automatic replay', () {
    const policy = FableRetryPolicy();
    expect(policy.canRetryMethod('GET'), isTrue);
    expect(policy.canRetryMethod('HEAD'), isTrue);
    for (final method in ['POST', 'PATCH', 'PUT', 'DELETE']) {
      expect(policy.canRetryMethod(method), isFalse);
    }
    expect(policy.retryableStatus(401), isFalse);
    expect(policy.retryableStatus(403), isFalse);
    expect(policy.retryableStatus(429), isTrue);
    expect(policy.retryableStatus(503), isTrue);
  });

  test('Backoff is bounded and respects Retry-After limits', () {
    const policy = FableRetryPolicy(baseDelay: Duration(milliseconds: 150),
      maxDelay: Duration(seconds: 2));
    expect(policy.backoff(0, retryAfter: '0'), Duration.zero);
    expect(policy.backoff(0, retryAfter: '1'), const Duration(seconds: 1));
    expect(policy.backoff(0, retryAfter: '30'), isNull);
    expect(policy.backoff(0, retryAfter: 'Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
    final delay = policy.backoff(2)!;
    expect(delay, lessThanOrEqualTo(const Duration(seconds: 2)));
    expect(delay, greaterThanOrEqualTo(Duration.zero));
  });

  test('Invalid unbounded retry policies fail closed', () {
    expect(() => const FableRetryPolicy(maxReadRetries: 10).validate(),
      throwsArgumentError);
    expect(() => const FableRetryPolicy(baseDelay: Duration(seconds: 3),
      maxDelay: Duration(seconds: 2)).validate(), throwsArgumentError);
  });

  test('Never replay TLS failures, cancellations or auth errors', () {
    const policy = FableRetryPolicy();
    for (final type in [DioExceptionType.badCertificate,
      DioExceptionType.cancel, DioExceptionType.badResponse,
      DioExceptionType.unknown]) {
      final exception = DioException(requestOptions: RequestOptions(path: '/'),
        type: type);
      expect(policy.retryableTransport(exception), isFalse);
    }
  });
}
