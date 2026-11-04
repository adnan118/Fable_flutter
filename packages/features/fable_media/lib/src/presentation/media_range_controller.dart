import 'dart:async';
import 'package:flutter/foundation.dart';
import '../application/read_media_range_use_case.dart';
import '../domain/media_byte_range.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';

/// Presentation-only states. No transport, JSON, credentials or server strings.
sealed class MediaRangeUiState {
  const MediaRangeUiState();
}
final class MediaRangeIdle extends MediaRangeUiState {
  const MediaRangeIdle();
}
final class MediaRangeLoading extends MediaRangeUiState {
  const MediaRangeLoading({required this.refreshing});
  final bool refreshing;
}
final class MediaRangeReady extends MediaRangeUiState {
  MediaRangeReady(Uint8List bytes):_bytes=Uint8List.fromList(bytes);
  final Uint8List _bytes;
  Uint8List get bytes=>Uint8List.fromList(_bytes);
}
final class MediaRangeFailureState extends MediaRangeUiState {
  const MediaRangeFailureState(this.reason);
  final MediaReadFailureKind reason;
}

/// May be wrapped by Riverpod/Bloc at a generated project's composition root.
/// Only invokes a typed use case. The UI localizes MediaReadFailureKind.
final class MediaRangeController extends ChangeNotifier {
  MediaRangeController(this._read){
    _subscription=_read.invalidations.listen((_){
      if(_disposed)return;
      // Purge previously displayed bytes synchronously on A->B account change,
      // credential rotation, server end, or source close.
      _generation++;
      _last=null;
      _read.cancelPendingReads();
      _publish(const MediaRangeIdle());
    });
  }
  final ReadMediaRangeUseCase _read;
  late final StreamSubscription<MediaSessionInvalidation> _subscription;
  MediaRangeUiState _state=const MediaRangeIdle();
  MediaRangeUiState get state=>_state;
  MediaByteRange? _last;
  int _generation=0;
  bool _disposed=false;

  Future<void> load(MediaByteRange request)async{
    if(_disposed||_state is MediaRangeLoading)return;
    final requestId=++_generation;
    _last=request;
    final wasReady=_state is MediaRangeReady;
    _publish(MediaRangeLoading(refreshing:wasReady));
    final result=await _read(request);
    if(_disposed||requestId!=_generation)return;
    switch(result){
      case MediaReadSuccess success:
        _publish(MediaRangeReady(success.bytes));
      case MediaReadFailed failed:
        _publish(MediaRangeFailureState(failed.failure.kind));
    }
  }

  Future<void> refresh()async{
    final value=_last;
    if(value==null || _disposed || _state is MediaRangeLoading)return;
    await load(value);
  }

  /// Drop the displayed bytes when a parent changes account/content/session.
  void reset(){
    if(_disposed)return;
    _generation++;
    _last=null;
    _read.cancelPendingReads();
    _publish(const MediaRangeIdle());
  }

  void _publish(MediaRangeUiState value){
    if(_disposed)return;
    _state=value;
    notifyListeners();
  }

  @override void dispose(){
    _disposed=true;
    _generation++;
    _last=null;
    _read.cancelPendingReads();
    unawaited(_subscription.cancel());
    _state=const MediaRangeIdle();
    super.dispose();
  }
}
