import 'dart:async';
import '../domain/media_byte_range.dart';
import '../domain/media_byte_source.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';

/// Domain-facing orchestration. No Flutter, Dio, JSON, endpoint or credentials.
final class ReadMediaRangeUseCase {
  const ReadMediaRangeUseCase(this.source);
  final MediaByteSource source;

  /// Session events are optional: non-protected sources retain their original
  /// contract. A native player can subscribe without importing Fable or Dio.
  Stream<MediaSessionInvalidation> get invalidations {
    final current=source;
    return current is SessionBoundMediaByteSource
        ? current.invalidations
        : const Stream<MediaSessionInvalidation>.empty();
  }

  void cancelPendingReads(){
    final current=source;
    if(current is SessionBoundMediaByteSource)current.cancelPendingReads();
  }

  bool get isSourceActive {
    final current=source;
    return current is! SessionBoundMediaByteSource || current.isActive;
  }

  Future<MediaReadResult> call(MediaByteRange range) async {
    if(!range.isValid){
      return const MediaReadFailed(
        MediaReadFailure(MediaReadFailureKind.invalidInput));
    }
    try{
      if(!isSourceActive){
        return const MediaReadFailed(
          MediaReadFailure(MediaReadFailureKind.sessionChanged));
      }
      final bytes=await source.read(range);
      if(!isSourceActive){
        return const MediaReadFailed(
          MediaReadFailure(MediaReadFailureKind.sessionChanged));
      }
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
