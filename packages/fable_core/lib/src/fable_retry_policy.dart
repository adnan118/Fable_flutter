import 'dart:math';
import 'package:dio/dio.dart';

/// Conservative and bounded HTTP resilience. Never replay writes automatically.
/// This policy is backend-neutral: it depends on HTTP semantics, not Fable paths.
class FableRetryPolicy {
  const FableRetryPolicy({
    this.maxReadRetries = 1,
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 2),
  });

  final int maxReadRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  void validate() {
    if (maxReadRetries < 0 || maxReadRetries > 3 ||
        baseDelay.isNegative || maxDelay.isNegative ||
        baseDelay > maxDelay || maxDelay > const Duration(seconds: 10)) {
      throw ArgumentError('Invalid bounded retry policy');
    }
  }

  bool canRetryMethod(String method) => method == 'GET' || method == 'HEAD';

  bool retryableStatus(int status) =>
      const <int>{429, 502, 503, 504}.contains(status);

  bool retryableTransport(DioException error) =>
      const <DioExceptionType>{
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      }.contains(error.type);

  /// Return null when the server requests a longer pause than the permitted
  /// foreground retry budget or the Retry-After format is not understood.
  Duration? backoff(int retryIndex, {String? retryAfter}) {
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds == null || seconds < 0) return null;
      final serverDelay = Duration(seconds: seconds);
      return serverDelay <= maxDelay ? serverDelay : null;
    }
    final exp = min(1 << min(retryIndex, 6), 64);
    final raw = baseDelay.inMilliseconds * exp;
    final cap = min(raw, maxDelay.inMilliseconds);
    // Jitter avoids many clients retrying in lockstep during outages.
    return Duration(milliseconds: cap == 0 ? 0 : Random().nextInt(cap + 1));
  }
}
