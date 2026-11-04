import 'dart:typed_data';

/// Stable, presentation-safe failure classification; never carries secrets,
/// raw HTTP responses, exception strings, or server-controlled error payloads.
enum MediaReadFailureKind {
  invalidInput,
  unauthenticated,
  forbidden,
  sessionChanged,
  expired,
  cancelled,
  offline,
  timedOut,
  rateLimited,
  unsupported,
  invalidResponse,
  serverUnavailable,
  unknown,
}

final class MediaReadFailure implements Exception {
  const MediaReadFailure(this.kind);
  final MediaReadFailureKind kind;
  bool get retryable => switch(kind){
    MediaReadFailureKind.offline ||
    MediaReadFailureKind.timedOut ||
    MediaReadFailureKind.serverUnavailable => true,
    _ => false,
  };
  @override String toString()=>'MediaReadFailure($kind)';
}

sealed class MediaReadResult {
  const MediaReadResult();
}

final class MediaReadSuccess extends MediaReadResult {
  MediaReadSuccess(Uint8List bytes) : _bytes=Uint8List.fromList(bytes);
  final Uint8List _bytes;
  /// Return a copy so a caller cannot mutate the stored result.
  Uint8List get bytes=>Uint8List.fromList(_bytes);
  int get length=>_bytes.length;
}

final class MediaReadFailed extends MediaReadResult {
  const MediaReadFailed(this.failure);
  final MediaReadFailure failure;
}
