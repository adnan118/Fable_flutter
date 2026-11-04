import 'dart:typed_data';
import 'media_byte_range.dart';
import 'media_session_bound_source.dart';

/// Verified metadata for a *single* protected byte range.
/// Values must come from a validated 206 + Content-Range response, not from
/// an asset URL, filename, player guess, or caller-supplied headers.
final class MediaByteChunk {
  MediaByteChunk({
    required this.start,
    required this.totalLength,
    required this.mimeType,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes) {
    if (start < 0 || totalLength <= 0 ||
        totalLength > 0x7fffffffffffffff ||
        _bytes.isEmpty || _bytes.length > MediaByteRange.maxLength ||
        start >= totalLength || _bytes.length > totalLength - start) {
      throw ArgumentError('Invalid verified media range metadata');
    }
    // Keep generic protected byte-range consumers compatible with RC113.
    // Only the optional native-player readChunk port requires audio/video.
    if (mimeType.isEmpty || mimeType.startsWith('text/html')) {
      throw const FormatException('Invalid protected media content type');
    }
  }

  final int start;
  final int totalLength;
  final String mimeType;
  final Uint8List _bytes;

  int get length => _bytes.length;

  /// Never expose the internal buffer to a caller or native bridge.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Optional, additive native-player capability. Older byte-only clients and
/// independent Other Backend adapters keep their existing interface.
abstract interface class DescribedMediaByteSource
    implements SessionBoundMediaByteSource {
  Future<MediaByteChunk> readChunk(MediaByteRange range);
}
