import 'dart:typed_data';
import 'media_byte_range.dart';

/// Session-bound capability, independent of any particular backend or player.
/// Fable, a separately verified external backend, or a local test fake MAY
/// implement it. An implementation must return only validated range bytes.
abstract interface class MediaByteSource {
  Future<Uint8List> read(MediaByteRange range);
}
