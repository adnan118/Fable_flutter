import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import '../domain/media_byte_range.dart';
import '../domain/media_byte_chunk.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';
import '../protected_media_playback_repository.dart';

/// Fable-specific adapter. Other Backend MUST implement MediaByteSource using
/// its own independently verified contract, auth policy and response parser.
final class FableMediaByteSource implements DescribedMediaByteSource {
  FableMediaByteSource({
    required this.repository,
    required this.playback,
  }) {
    _invalidated=!repository.isCurrentView(playback);
    _subscription=repository.invalidations.listen((change){
      if(_closed||_invalidated)return;
      _invalidated=true;
      _signals.add(switch(change){
        ProtectedPlaybackInvalidation.accountChanged =>
          MediaSessionInvalidation.accountChanged,
        ProtectedPlaybackInvalidation.credentialsRotated =>
          MediaSessionInvalidation.credentialsRotated,
        ProtectedPlaybackInvalidation.playbackEnded =>
          MediaSessionInvalidation.playbackEnded,
        ProtectedPlaybackInvalidation.disposed =>
          MediaSessionInvalidation.sourceClosed,
      });
    });
  }
  final FableProtectedMediaPlaybackRepository repository;
  final ProtectedMediaPlaybackView playback;
  final StreamController<MediaSessionInvalidation> _signals=
      StreamController<MediaSessionInvalidation>.broadcast(sync:true);
  StreamSubscription<ProtectedPlaybackInvalidation>? _subscription;
  bool _closed=false;
  bool _invalidated=false;
  int? _knownTotalLength;
  String? _knownMimeType;

  @override Stream<MediaSessionInvalidation> get invalidations=>_signals.stream;
  @override bool get isActive=>
      !_closed && !_invalidated && repository.isCurrentView(playback);

  @override void cancelPendingReads(){
    if(!_closed)repository.cancelReadsForView(playback);
  }

  @override Future<void> close() async {
    if(_closed)return;
    _closed=true;
    _invalidated=true;
    repository.cancelReadsForView(playback);
    _signals.add(MediaSessionInvalidation.sourceClosed);
    await _subscription?.cancel();
    _subscription=null;
    await _signals.close();
  }

  @override
  Future<Uint8List> read(MediaByteRange range) async =>
      (await readChunk(range)).bytes;

  @override
  Future<MediaByteChunk> readChunk(MediaByteRange range) async {
    if(!range.isValid){
      throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    }
    if(!isActive){
      throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    }
    try{
      final chunk=await repository.readContentRangeChunk(playback,
        start:range.start,length:range.length);
      if(!isActive){
        throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
      }
      // Seek and native buffers must never combine bytes from revisions
      // reporting different sizes or MIME types within the same view.
      if((_knownTotalLength!=null &&
          _knownTotalLength!=chunk.totalLength) ||
         (_knownMimeType!=null && _knownMimeType!=chunk.mimeType)){
        throw const MediaReadFailure(MediaReadFailureKind.invalidResponse);
      }
      _knownTotalLength=chunk.totalLength;
      _knownMimeType=chunk.mimeType;
      return chunk;
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
      // A superseded playback view is different from an expired active token.
      // Do not publish StateError.toString(): it may carry server details.
      throw MediaReadFailure(isActive
        ? MediaReadFailureKind.expired
        : MediaReadFailureKind.sessionChanged);
    } on ArgumentError {
      throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    }
  }
}
