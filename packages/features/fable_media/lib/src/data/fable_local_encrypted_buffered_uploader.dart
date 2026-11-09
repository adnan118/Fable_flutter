import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:fable_core/fable_core.dart';
import '../domain/media_read_models.dart';

/// RC137 Fable-only LOCAL tier uploader. Other Backend MUST supply its own
/// explicitly verified upload port/operation, never reuse /media by guessing.
final class FableLocalEncryptedBufferedUploader {
  FableLocalEncryptedBufferedUploader({
    required this.gateway,
    required BackendSelection selectedBackend,
    required OperationCatalog catalog,
    required this.runtime,
    required int Function() identityRevision,
    required bool Function() isSessionCurrent,
  }) : _revision=identityRevision,
       _sessionCurrent=isSessionCurrent {
    // A Fable route must not be dispatched through an Other/OpenAPI custom
    // backend, even if its catalog happens to contain the same operation ID.
    if(!selectedBackend.canUseFableContract || catalog is! FableContract)
      throw StateError('Verified Fable Backend selection and contract required');
    final operation=catalog.require('media.upload');
    if(operation.method.toUpperCase()!='POST' ||
        operation.path!='/media' ||
        !operation.requiresAuth || !operation.enforceAuth) {
      throw StateError('Fable LOCAL upload operation is not verified');
    }
  }
  final BackendApiGateway gateway;
  final MediaMetadataReadPort runtime;
  final int Function() _revision;
  final bool Function() _sessionCurrent;

  Future<String> upload({
    required File file,
    required String kind,
    required String mimeType,
    String visibility='PRIVATE',
    String? purpose,
    CancelToken? cancelToken,
  }) async {
    if(!const {'IMAGE','VIDEO','AUDIO','DOCUMENT'}.contains(kind) ||
        !const {'PRIVATE','PUBLIC'}.contains(visibility) ||
        !RegExp(r'^[a-z0-9][a-z0-9.+_-]*/[a-z0-9][a-z0-9.+_-]*$')
            .hasMatch(mimeType) ||
        (purpose!=null&&(purpose.isEmpty||purpose.length>80))) {
      throw ArgumentError('Invalid Fable LOCAL media metadata');
    }
    final generation=_revision();
    void fence(){
      if(!_sessionCurrent()||_revision()!=generation||
          (cancelToken?.isCancelled??false)) {
        throw StateError('Media identity changed or upload cancelled');
      }
    }
    fence();
    final capabilities=await runtime.runtimeContract();
    fence();
    // Do NOT silently fall back to unencrypted resumable or unverified API.
    if(!capabilities.encryptionTierVerified ||
        capabilities.encryptionTier!=MediaEncryptionTier.local ||
        capabilities.resumableLargeUpload ||
        capabilities.directPresignedMultipart ||
        capabilities.maxUploadBytes<1) {
      throw StateError('Verified Fable LOCAL buffered-upload contract required');
    }
    final length=await file.length();
    fence();
    if(length<=0||length>capabilities.maxUploadBytes)
      throw RangeError('File exceeds Fable LOCAL encrypted-upload limit');
    final name=file.uri.pathSegments.last;
    if(name.isEmpty||name.length>255)
      throw ArgumentError('Invalid media file name');
    final upload=await MultipartFile.fromFile(file.path,
      filename:name,contentType:MediaType.parse(mimeType));
    fence();
    final body=FormData.fromMap({
      'kind':kind,'visibility':visibility,
      if(purpose!=null)'purpose':purpose,
      'file':upload,
    });
    final result=await gateway.execute('media.upload',
      body:body,cancelToken:cancelToken);
    fence();
    final envelope=result.data;
    if(envelope is! Map||envelope['success']==false)
      throw const FormatException('Invalid Fable media upload response');
    final payload=envelope['data'] is Map?envelope['data']:envelope;
    if(payload is! Map)throw const FormatException('Invalid Fable media record');
    final id=payload['id'];
    final access=payload['access'];
    if(id is! String||!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      caseSensitive:false).hasMatch(id) ||
      access is! Map || access['type']!='protected' ||
      access['url']!=null ||
      access['playbackEndpoint']!='/media/$id/playback') {
      throw const FormatException('Fable LOCAL response violates private media contract');
    }
    return id;
  }
}
