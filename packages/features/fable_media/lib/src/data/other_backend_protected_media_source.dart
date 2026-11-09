import 'dart:async';
import 'dart:typed_data';
import '../domain/media_byte_range.dart';
import '../domain/media_byte_chunk.dart';
import '../domain/media_read_result.dart';
import '../domain/media_session_bound_source.dart';
import '../domain/media_read_models.dart';

/// RC137 — The OTHER-Backend bridge is explicit, not guessed from a Fable
/// catalog. Each outside Backend MUST implement and independently verify
/// its own HTTP contract, authentication, status/Content-Range parser and
/// revocation mechanism; no Fable routes, cookies, tokens or user IDs here.
abstract interface class OtherBackendVerifiedMediaTransport {
  Future<MediaByteChunk> readVerifiedRange(MediaByteRange range);
  Stream<MediaSessionInvalidation> get invalidations;
  bool get isAuthorized;
  void cancelPendingReads();
  Future<void> close();
}

/// No keys or bearer URLs. A claimed tier does not enable another Backend's
/// security: its integrator must first verify the published server contract.
final class OtherBackendMediaDeclaration {
  OtherBackendMediaDeclaration({
    required this.backendId,
    required this.encryptionTier,
    required this.authorizationDeadline,
    required this.privateByteStorage,
    required this.everyRangeAuthorized,
    required this.noPublicDownloadUrl,
    required this.clientReceivesNoKey,
    required this.contractVerified,
    required this.licensedDrmVerified,
  }) {
    if (backendId.trim().isEmpty || backendId.length>128 ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(backendId) ||
        !privateByteStorage || !everyRangeAuthorized ||
        !noPublicDownloadUrl || !clientReceivesNoKey || !contractVerified ||
        (encryptionTier==MediaEncryptionTier.drm && !licensedDrmVerified)) {
      throw StateError('External media backend has not been independently verified');
    }
    if (authorizationDeadline.isUtc==false) {
      throw ArgumentError('External media deadline must use UTC');
    }
  }
  final String backendId;
  final MediaEncryptionTier encryptionTier;
  final DateTime authorizationDeadline;
  final bool privateByteStorage, everyRangeAuthorized;
  final bool noPublicDownloadUrl, clientReceivesNoKey, contractVerified;
  final bool licensedDrmVerified;
}

/// Source bound to one external backend's own session and one identity
/// revision. No global Fable AuthGateway is imported, shared or used.
/// A separate instance MUST be created after every account/backend switch.
final class OtherBackendProtectedMediaSource
    implements DescribedMediaByteSource {
  OtherBackendProtectedMediaSource({
    required OtherBackendMediaDeclaration declaration,
    required OtherBackendVerifiedMediaTransport transport,
    required int Function() identityRevision,
  }) : _declaration=declaration,
       _transport=transport,
       _identityRevision=identityRevision,
       _boundIdentity=identityRevision() {
    _subscription=_transport.invalidations.listen((reason){
      _invalidate(reason);
    });
  }
  final OtherBackendMediaDeclaration _declaration;
  final OtherBackendVerifiedMediaTransport _transport;
  final int Function() _identityRevision;
  final int _boundIdentity;
  final StreamController<MediaSessionInvalidation> _signals =
      StreamController<MediaSessionInvalidation>.broadcast(sync:true);
  StreamSubscription<MediaSessionInvalidation>? _subscription;
  bool _closed=false,_invalidated=false;
  int? _total;
  String? _mime;

  MediaEncryptionTier get encryptionTier=>_declaration.encryptionTier;
  String get backendId=>_declaration.backendId;
  @override DateTime get authorizationDeadline=>_declaration.authorizationDeadline;
  @override Stream<MediaSessionInvalidation> get invalidations=>_signals.stream;
  @override bool get isActive=>
      !_closed && !_invalidated &&
      _transport.isAuthorized &&
      _identityRevision()==_boundIdentity &&
      DateTime.now().toUtc().isBefore(authorizationDeadline);

  void _invalidate(MediaSessionInvalidation reason){
    if(_invalidated||_closed)return;
    _invalidated=true;
    _transport.cancelPendingReads();
    if(!_signals.isClosed)_signals.add(reason);
  }

  @override void cancelPendingReads(){
    if(!_closed)_transport.cancelPendingReads();
  }

  @override Future<Uint8List> read(MediaByteRange range) async {
    final chunk=await _readGuarded(range,requireProgressive:false);
    if(!isActive)throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    return chunk.bytes;
  }

  @override Future<MediaByteChunk> readChunk(MediaByteRange range) =>
      _readGuarded(range,requireProgressive:true);

  Future<MediaByteChunk> _readGuarded(MediaByteRange range,{
    required bool requireProgressive,
  }) async {
    if(!range.isValid)throw const MediaReadFailure(MediaReadFailureKind.invalidInput);
    // Generic clear byte-range transports are NEVER CDM/DRM renderers.
    // Even a licensed DRM declaration requires a separately verified native
    // or browser DRM license/player adapter. Do not fall back to clear ranges.
    if(_declaration.encryptionTier==MediaEncryptionTier.drm)
      throw const MediaReadFailure(MediaReadFailureKind.unsupported);
    if(!isActive){
      _invalidate(MediaSessionInvalidation.accountChanged);
      throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
    }
    final snapshot=_boundIdentity;
    try{
      final chunk=await _transport.readVerifiedRange(range);
      if(!isActive||_identityRevision()!=snapshot){
        _invalidate(MediaSessionInvalidation.accountChanged);
        throw const MediaReadFailure(MediaReadFailureKind.sessionChanged);
      }
      final expected=range.start<chunk.totalLength
          ? (range.length<chunk.totalLength-range.start
              ? range.length : chunk.totalLength-range.start)
          : 0;
      if(chunk.start!=range.start || chunk.length!=expected ||
          (_total!=null&&_total!=chunk.totalLength) ||
          (_mime!=null&&_mime!=chunk.mimeType)){
        _invalidate(MediaSessionInvalidation.resourceChanged);
        throw const MediaReadFailure(MediaReadFailureKind.invalidResponse);
      }
      if(requireProgressive &&
          !RegExp(r'^(audio|video)/[a-z0-9][a-z0-9.+_-]*
      return chunk;
    } on MediaReadFailure catch(error) {
      if(const {MediaReadFailureKind.unauthenticated,
            MediaReadFailureKind.forbidden,
            MediaReadFailureKind.expired,
            MediaReadFailureKind.sessionChanged}.contains(error.kind)) {
        _invalidate(MediaSessionInvalidation.playbackEnded);
      }
      rethrow;
    } catch(_){
      // Do not leak external server HTTP data / secrets into UI messages.
      throw const MediaReadFailure(MediaReadFailureKind.unknown);
    }
  }

  @override Future<void> close() async{
    if(_closed)return;
    _closed=true;
    _transport.cancelPendingReads();
    await _subscription?.cancel();
    try { await _transport.close(); } finally {
      await _signals.close();
    }
  }
}

/// An explicit composition-root choice. The external factory and its
/// verification belong to the selected outside Backend, not Fable.
enum ProjectMediaBackendKind { fable, other }

final class ProjectMediaBackendBinding {
  ProjectMediaBackendBinding({
    required this.kind,
    required this.backendId,
    required this.openProtectedSource,
  }){
    if(backendId.trim().isEmpty)throw ArgumentError('Backend identity required');
  }
  final ProjectMediaBackendKind kind;
  final String backendId;
  final Future<DescribedMediaByteSource> Function(String assetId)
      openProtectedSource;
}
).hasMatch(chunk.mimeType)){
        _invalidate(MediaSessionInvalidation.resourceChanged);
        throw const MediaReadFailure(MediaReadFailureKind.unsupported);
      }
      _total=chunk.totalLength;
      _mime=chunk.mimeType;
      return chunk;
    } on MediaReadFailure catch(error) {
      if(const {MediaReadFailureKind.unauthenticated,
            MediaReadFailureKind.forbidden,
            MediaReadFailureKind.expired,
            MediaReadFailureKind.sessionChanged}.contains(error.kind)) {
        _invalidate(MediaSessionInvalidation.playbackEnded);
      }
      rethrow;
    } catch(_){
      // Do not leak external server HTTP data / secrets into UI messages.
      throw const MediaReadFailure(MediaReadFailureKind.unknown);
    }
  }

  @override Future<void> close() async{
    if(_closed)return;
    _closed=true;
    _transport.cancelPendingReads();
    await _subscription?.cancel();
    try { await _transport.close(); } finally {
      await _signals.close();
    }
  }
}

/// An explicit composition-root choice. The external factory and its
/// verification belong to the selected outside Backend, not Fable.
enum ProjectMediaBackendKind { fable, other }

final class ProjectMediaBackendBinding {
  ProjectMediaBackendBinding({
    required this.kind,
    required this.backendId,
    required this.openProtectedSource,
  }){
    if(backendId.trim().isEmpty)throw ArgumentError('Backend identity required');
  }
  final ProjectMediaBackendKind kind;
  final String backendId;
  final Future<DescribedMediaByteSource> Function(String assetId)
      openProtectedSource;
}
