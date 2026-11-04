import '../domain/media_byte_range.dart';
import '../domain/media_byte_source.dart';
import '../domain/media_read_result.dart';

/// Domain-facing orchestration. No Flutter, Dio, JSON, endpoint or credentials.
final class ReadMediaRangeUseCase {
  const ReadMediaRangeUseCase(this.source);
  final MediaByteSource source;

  Future<MediaReadResult> call(MediaByteRange range) async {
    if(!range.isValid){
      return const MediaReadFailed(
        MediaReadFailure(MediaReadFailureKind.invalidInput));
    }
    try{
      final bytes=await source.read(range);
      if(bytes.isEmpty || bytes.length>range.length){
        return const MediaReadFailed(
          MediaReadFailure(MediaReadFailureKind.invalidResponse));
      }
      return MediaReadSuccess(bytes);
    } on MediaReadFailure catch(failure){
      return MediaReadFailed(failure);
    } catch(_){
      // Never leak a server error map, auth header, stack trace or raw token
      // into presentation. The data adapter handles detailed classification.
      return const MediaReadFailed(
        MediaReadFailure(MediaReadFailureKind.unknown));
    }
  }
}
