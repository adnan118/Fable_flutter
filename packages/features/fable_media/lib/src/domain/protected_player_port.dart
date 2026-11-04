import 'media_byte_chunk.dart';
import 'media_read_result.dart';

/// Player-visible phases. Nothing here is tied to Flutter, Media3, AVFoundation
/// or a particular Backend. Renderer state is authoritative only in a native
/// adapter that passes independent platform/device verification.
enum ProtectedPlayerPhase {
  idle,
  preparing,
  ready,
  playing,
  paused,
  stopped,
  revoked,
  failed,
  disposed,
}

final class ProtectedPlayerState {
  const ProtectedPlayerState(this.phase, {this.failure});
  final ProtectedPlayerPhase phase;
  final MediaReadFailureKind? failure;
}

/// Only independently verified Content-Range metadata; never a network URL,
/// a media-token, an authorization header or an asset/account identifier.
final class ProtectedPlayerMetadata {
  const ProtectedPlayerMetadata({
    required this.totalLength,
    required this.mimeType,
  });
  final int totalLength;
  final String mimeType;
}

final class ProtectedPlayerReadRequest {
  const ProtectedPlayerReadRequest({
    required this.requestId,
    required this.start,
    required this.length,
  });
  final int requestId;
  final int start;
  final int length;
}

sealed class ProtectedPlayerReadReply {
  const ProtectedPlayerReadReply();
}

final class ProtectedPlayerBytes extends ProtectedPlayerReadReply {
  const ProtectedPlayerBytes(this.chunk);
  final MediaByteChunk chunk;
}

final class ProtectedPlayerEndOfFile extends ProtectedPlayerReadReply {
  const ProtectedPlayerEndOfFile();
}

final class ProtectedPlayerReadRejected extends ProtectedPlayerReadReply {
  const ProtectedPlayerReadRejected(this.reason);
  final MediaReadFailureKind reason;
}

typedef ProtectedPlayerRangeReader = Future<ProtectedPlayerReadReply> Function(
  ProtectedPlayerReadRequest request,
);

/// Platform-owned renderer port. prepare() MUST register the bounded reader,
/// never invent URLs or credentials, and ensure stop() cancels in-progress
/// prepare/reads and flushes decoder buffers before any next session.
abstract interface class ProtectedPlayerPlatformPort {
  Future<void> prepare(
    ProtectedPlayerMetadata metadata,
    ProtectedPlayerRangeReader read,
  );
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
