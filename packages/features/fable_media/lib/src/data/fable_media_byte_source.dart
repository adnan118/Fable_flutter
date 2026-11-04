import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import '../domain/media_byte_range.dart';
import '../domain/media_byte_source.dart';
import '../domain/media_read_result.dart';
import '../protected_media_playback_repository.dart';

/// Fable-specific adapter. Other Backend MUST implement MediaByteSource using
/// its own independently verified contract, auth policy and response parser.
final class FableMediaByteSource implements MediaByteSource {
  const FableMediaByteSource({
    required this.repository,
    required this.playback,
  });
  final FableProtectedMediaPlaybackRepository repository;
  final ProtectedMediaPlaybackView playback;

  @override
  Future<Uint8List> read(MediaByteRange range) async {
    if(!range.isValid){
      throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    }
    try{
      return await repository.readContentRange(playback,
        start:range.start,length:range.length);
    } on FableApiException catch(error){
      if(error.status==401){
        throw const MediaReadFailure(MediaReadFailureKind.unauthenticated);
      }
      if(error.status==403){
        throw const MediaReadFailure(MediaReadFailureKind.forbidden);
      }
      if(error.status==409 || error.code=='session_changed_discard_response'){
        throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
      }
      if(error.code=='request_cancelled'){
        throw const MediaReadFailure(MediaReadFailureKind.cancelled);
      }
      if(error.status==408 || error.status==504){
        throw const MediaReadFailure(MediaReadFailureKind.timedOut);
      }
      if(error.status==429){
        throw const MediaReadFailure(MediaReadFailureKind.rateLimited);
      }
      if(error.status>=500){
        throw const MediaReadFailure(MediaReadFailureKind.serverUnavailable);
      }
      throw const MediaReadFailure(MediaReadFailureKind.unknown);
    } on TimeoutException {
      throw const MediaReadFailure(MediaReadFailureKind.timedOut);
    } on DioException catch(error){
      if(error.type==DioExceptionType.cancel){
        throw const MediaReadFailure(MediaReadFailureKind.cancelled);
      }
      throw const MediaReadFailure(MediaReadFailureKind.offline);
    } on FormatException {
      throw const MediaReadFailure(MediaReadFailureKind.invalidResponse);
    } on StateError {
      // Do not publish StateError.toString(): can contain server details.
      throw const MediaReadFailure(MediaReadFailureKind.expired);
    } on ArgumentError {
      throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    }
  }
}
