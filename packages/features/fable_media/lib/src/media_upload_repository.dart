import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';

/// Media is OPTIONAL. The app's selected backend contract is authoritative.
/// Fable uses these operation IDs; Other Backend MUST explicitly map every role
/// from its own verified contract and provide a suitable binary transport.
class MediaUploadBindings {
  const MediaUploadBindings({required this.prepare, required this.status,
    required this.chunk, required this.partUrl, required this.partAck,
    required this.complete, required this.abort});
  const MediaUploadBindings.fable()
      : prepare = 'media.upload.prepare', status = 'media.upload.status',
        chunk = 'media.upload.chunk', partUrl = 'media.upload.partUrl',
        partAck = 'media.upload.partAck', complete = 'media.upload.complete',
        abort = 'media.upload.abort';
  /// Explicitly wired from a VERIFIED non-Fable feature-operations.json.
  /// These are operation IDs, never guessed paths. Do not pass Fable defaults.
  factory MediaUploadBindings.other(Map<String,String> roles) {
    const required=['upload.prepare','upload.status','upload.chunk','upload.partUrl',
      'upload.partAck','upload.complete','upload.abort'];
    if(roles.length!=required.length || required.any((key)=>
        roles[key]==null || roles[key]!.isEmpty)) {
      throw ArgumentError('Other Backend Media requires seven explicit mapped operation roles');
    }
    return MediaUploadBindings(prepare:roles['upload.prepare']!,status:roles['upload.status']!,
      chunk:roles['upload.chunk']!,partUrl:roles['upload.partUrl']!,
      partAck:roles['upload.partAck']!,complete:roles['upload.complete']!,
      abort:roles['upload.abort']!);
  }
  final String prepare, status, chunk, partUrl, partAck, complete, abort;

  /// Fail before uploading anything if the imported contract is incomplete.
  void verify(OperationCatalog catalog) {
    final required = <String, String>{
      prepare:'POST', status:'GET', chunk:'POST', partUrl:'POST',
      partAck:'POST', complete:'POST', abort:'DELETE',
    };
    if (required.length != 7) throw StateError('Upload roles must be unique');
    for (final role in required.entries) {
      final op = catalog.require(role.key);
      if (op.method.toUpperCase() != role.value || !op.requiresAuth || !op.enforceAuth) {
        throw StateError('Unverified protected media upload operation: ${role.key}');
      }
    }
  }
}

class MediaUploadProgress {
  const MediaUploadProgress(this.uploadedBytes, this.totalBytes, this.percentage);
  final int uploadedBytes, totalBytes;
  final num percentage;
}

/// The local file must be confirmed unchanged when restoring an upload session.
/// Store this checkpoint using OS-backed app storage, scoped to backend+account.
/// NEVER persist the presigned URL (it is a temporary bearer credential).
class MediaUploadCheckpoint {
  const MediaUploadCheckpoint({required this.sessionId, required this.sha256,
    required this.sizeBytes});
  final String sessionId, sha256;
  final int sizeBytes;
  Map<String,dynamic> toJson()=>{'sessionId':sessionId,'sha256':sha256,'sizeBytes':sizeBytes};
  factory MediaUploadCheckpoint.fromJson(Map<String,dynamic> data) {
    final id=data['sessionId'],digest=data['sha256'],size=data['sizeBytes'];
    if(id is! String || !RegExp(r'^[a-f\d]{8}-[a-f\d]{4}-4[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$',caseSensitive:false).hasMatch(id) ||
       digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) || size is! int || size<=0) {
      throw const FormatException('Invalid upload checkpoint');
    }
    return MediaUploadCheckpoint(sessionId:id,sha256:digest,sizeBytes:size);
  }
  Future<void> verify(File file) async {
    if (await file.length() != sizeBytes) throw StateError('File length changed; cannot resume');
    final digest = await sha256ForFile(file);
    if (digest != sha256) throw StateError('File bytes changed; cannot resume');
  }
  static Future<String> sha256ForFile(File file) async =>
      (await crypto.sha256.bind(file.openRead()).first).toString();
}

/// Persists ONLY opaque session id + local file fingerprint; no credentials,
/// signed URLs, paths or content. Caller MUST supply a SHA-256 scope over the
/// selected backend+authenticated account; never share checkpoints across users.
class MediaUploadCheckpointStore {
  MediaUploadCheckpointStore(this.scope, {SharedPreferencesAsync? preferences})
      : _prefs=preferences ?? SharedPreferencesAsync() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) throw ArgumentError('Use backend/account-scoped SHA-256 key');
  }
  final String scope;
  final SharedPreferencesAsync _prefs;
  String get _key=>'fable.media.resume.v1.$scope';
  Future<void> save(MediaUploadCheckpoint checkpoint) async {
    await _prefs.setString(_key,jsonEncode({'checkpoint':checkpoint.toJson(),
      'savedAt':DateTime.now().toUtc().toIso8601String()}));
  }
  Future<MediaUploadCheckpoint?> read() async {
    final raw=await _prefs.getString(_key);
    if(raw==null)return null;
    if(raw.length>2048){await clear();throw const FormatException('Oversized checkpoint');}
    try{
      final data=jsonDecode(raw);
      if(data is! Map || data['checkpoint'] is! Map || data['savedAt'] is! String)throw const FormatException('Invalid checkpoint');
      final saved=DateTime.parse(data['savedAt'] as String);
      final age=DateTime.now().toUtc().difference(saved);
      if(age.isNegative || age>const Duration(hours:12)){await clear();return null;}
      return MediaUploadCheckpoint.fromJson(Map<String,dynamic>.from(data['checkpoint'] as Map));
    }on FormatException{await clear();rethrow;}
  }
  Future<void> clear()=>_prefs.remove(_key);
}

/// The only component allowed to access a presigned external storage URL.
/// Other Backend implementations must provide their own strictly scoped
/// uploader rather than reusing a Fable-specific storage domain implicitly.
abstract interface class MediaPresignedPartTransport {
  /// Returns the provider's ETag, never the request URL or a bearer token.
  Future<String> putPart(Uri url, File file, int start, int end,
      {CancelToken? cancelToken});
  void dispose();
}

/// Cloudflare R2 uses an S3-compatible protocol, but not Amazon S3 storage.
/// Use a DEDICATED unauthenticated Dio, no redirect and no default headers.
class CloudflareR2PartTransport implements MediaPresignedPartTransport {
  CloudflareR2PartTransport({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
      followRedirects:false, connectTimeout:const Duration(seconds:10),
      receiveTimeout:const Duration(seconds:50), sendTimeout:const Duration(minutes:5)));
  final Dio _dio;
  static final _cloudflareHost = RegExp(
    r'^(?:[a-z0-9-]+\.)?[a-f0-9]{32}\.r2\.cloudflarestorage\.com$');

  static void validatePresignedUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasFragment || (uri.hasPort && uri.port != 443) ||
        !_cloudflareHost.hasMatch(uri.host.toLowerCase()) ||
        uri.queryParameters['X-Amz-Signature']?.isEmpty != false ||
        uri.queryParameters['X-Amz-Algorithm'] != 'AWS4-HMAC-SHA256') {
      throw StateError('Only signed Cloudflare R2 HTTPS upload URLs are accepted');
    }
  }

  @override
  Future<String> putPart(Uri url, File file, int start, int end,
      {CancelToken? cancelToken}) async {
    validatePresignedUri(url);
    if (start < 0 || end <= start || end > await file.length()) {
      throw RangeError('Invalid file part range');
    }
    if (_dio.interceptors.isNotEmpty || _dio.options.headers.keys.any((header) =>
        RegExp(r'(authorization|cookie|api.key|token|secret)',caseSensitive:false)
            .hasMatch(header.toString()))) {
      throw StateError('Presigned transport cannot hold ambient credentials');
    }
    try {
      final result = await _dio.putUri<void>(url,
        data:file.openRead(start,end), cancelToken:cancelToken,
        options:Options(headers:{'content-length':end-start},
          followRedirects:false, maxRedirects:0,
          contentType:'application/octet-stream',
          validateStatus:(status)=>status != null && status >= 200 && status < 300));
      final tag = result.headers.value('etag');
      if (tag == null || tag.isEmpty || tag.length > 300) {
        throw StateError('R2 did not return a valid ETag; do not acknowledge the part');
      }
      return tag;
    } on DioException {
      // The signed URL is a bearer credential; never include it in exceptions/logs.
      throw StateError('Cloudflare R2 part upload failed; request a fresh URL and inspect server status');
    }
  }
  @override void dispose() => _dio.close(force:true);
}

/// Resumes from SERVER-confirmed bytes/parts. Never assumes client-sent bytes
/// were committed. A failed mutation is NOT automatically replayed by Core.
class MediaUploadRepository {
  MediaUploadRepository({required this.gateway, required OperationCatalog catalog,
    required this.bindings, this.partTransport}) {
    bindings.verify(catalog);
  }
  final BackendApiGateway gateway;
  final MediaUploadBindings bindings;
  final MediaPresignedPartTransport? partTransport;

  static Map<String, dynamic> _body(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid backend media response');
    final nested = raw['data'];
    final data = nested is Map ? nested : raw;
    return Map<String, dynamic>.from(data);
  }
  static int _integer(Object? value, String name) {
    if (value is int) return value;
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      final v = int.tryParse(value);
      if (v != null) return v;
    }
    throw FormatException('Invalid $name returned by backend');
  }
  static String _id(String input) {
    if (!RegExp(r'^[a-f\d]{8}-[a-f\d]{4}-4[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$',caseSensitive:false).hasMatch(input)) {
      throw ArgumentError('Invalid upload session UUID');
    }
    return input;
  }
  static String _strategy(Map<String,dynamic> state) {
    final upload = state['upload'];
    if (upload is! Map || upload['strategy'] is! String) throw const FormatException('No upload strategy in server response');
    final strategy = upload['strategy'] as String;
    if (!const {'LOCAL_RESUMABLE','S3_MULTIPART'}.contains(strategy)) {
      throw StateError('Upload strategy not supported by this client; check backend contract');
    }
    return strategy;
  }
  static MediaUploadProgress _progress(Map<String,dynamic> state, int expectedSize) {
    final progress = state['progress'];
    if (progress is! Map) throw const FormatException('No server-confirmed progress');
    final bytes=_integer(progress['uploadedBytes'],'uploadedBytes');
    final total=_integer(progress['totalBytes'],'totalBytes');
    final pct=progress['percentage'];
    if (total!=expectedSize || bytes<0 || bytes>total || pct is! num || pct<0 || pct>100) {
      throw const FormatException('Inconsistent backend progress');
    }
    return MediaUploadProgress(bytes,total,pct);
  }
  static void _fileMatches(Map<String,dynamic> state,int size) {
    if (_integer(state['sizeBytes'],'sizeBytes')!=size) throw StateError('Session belongs to a different file size');
  }
  Future<Map<String,dynamic>> prepare(File file, {
    required String kind,required String mimeType,
    String? purpose,String visibility='PRIVATE'}) async {
    if (!const {'IMAGE','VIDEO','AUDIO','DOCUMENT'}.contains(kind) ||
        !const {'PUBLIC','PRIVATE'}.contains(visibility) ||
        mimeType.isEmpty || mimeType.length > 180 ||
        purpose != null && purpose.length > 80) throw ArgumentError('Invalid media metadata');
    final size=await file.length();
    if (size <= 0) throw ArgumentError('Cannot upload an empty file');
    final name=file.uri.pathSegments.last;
    if (name.isEmpty || name.length>255) throw ArgumentError('Invalid media file name');
    final response=await gateway.execute(bindings.prepare,body:{
      'kind':kind,'mimeType':mimeType,'originalName':name,'sizeBytes':size,
      'visibility':visibility,if(purpose!=null)'purpose':purpose,
    });
    final state=_body(response.data);
    _id(state['id'].toString());
    _strategy(state);
    _fileMatches(state,size);
    _progress(state,size);
    return state;
  }
  Future<Map<String,dynamic>> status(String sessionId) async =>
      _body((await gateway.execute(bindings.status,path:{'id':_id(sessionId)})).data);
  Future<Map<String,dynamic>> abort(String sessionId) async =>
      _body((await gateway.execute(bindings.abort,path:{'id':_id(sessionId)})).data);
  /// A user-initiated cancellation must durably stop any pending domain publish
  /// BEFORE contacting the backend, even if the DELETE request then fails.
  Future<Map<String,dynamic>> cancel(String sessionId, {
    required Future<void> Function(String sessionId) persistCancelIntent,
  }) async {
    _id(sessionId);
    await persistCancelIntent(sessionId);
    return abort(sessionId);
  }

  /// On restart the caller supplies a securely stored checkpoint scoped to
  /// account and backend. Re-hash the file before any new data is sent.
  Future<Map<String,dynamic>> start(File file, {required String kind, required String mimeType,
      String? purpose, String visibility='PRIVATE',
      required Future<void> Function(MediaUploadCheckpoint) saveCheckpoint,
      void Function(MediaUploadProgress)? onProgress, CancelToken? cancelToken}) async {
    final prepared=await prepare(file,kind:kind,mimeType:mimeType,
      purpose:purpose,visibility:visibility);
    final checkpoint=MediaUploadCheckpoint(
      sessionId:prepared['id'] as String,
      sha256:await MediaUploadCheckpoint.sha256ForFile(file),
      sizeBytes:await file.length());
    // Persist checkpoint before uploading a single chunk/part.
    await saveCheckpoint(checkpoint);
    return _transfer(file,checkpoint.sessionId,onProgress:onProgress,cancelToken:cancelToken);
  }
  Future<Map<String,dynamic>> resume(File file, MediaUploadCheckpoint checkpoint,
      {void Function(MediaUploadProgress)? onProgress,CancelToken? cancelToken}) async {
    await checkpoint.verify(file);
    return _transfer(file,checkpoint.sessionId,onProgress:onProgress,cancelToken:cancelToken);
  }
  Future<Map<String,dynamic>> _transfer(File file,String sessionId,
      {void Function(MediaUploadProgress)? onProgress,CancelToken? cancelToken}) async {
    _id(sessionId);
    final length=await file.length();
    var state=await status(sessionId);
    _fileMatches(state,length);
    final strategy=_strategy(state);
    final initial=_progress(state,length);
    onProgress?.call(initial);
    if (state['status']=='COMPLETED') return state;
    if (state['status']=='ABORTED' || state['status']=='EXPIRED') throw StateError('Upload session expired or was cancelled');
    if (strategy=='LOCAL_RESUMABLE') {
      int offset=_integer(state['nextOffsetBytes'],'nextOffsetBytes');
      final upload=state['upload'] as Map;
      final chunkSize=_integer(upload['chunkSizeBytes'],'chunkSizeBytes');
      if (chunkSize<1 || chunkSize>32*1024*1024 || offset>length) throw const FormatException('Invalid local chunk contract');
      while(offset<length){
        if(cancelToken?.isCancelled??false) throw StateError('Upload cancelled');
        final next=(offset+chunkSize>length)?length:offset+chunkSize;
        final binary=MultipartFile.fromStream(()=>file.openRead(offset,next),next-offset,filename:'chunk');
        final form=FormData.fromMap({'offset':offset.toString(),'chunk':binary});
        // Do not replay a failed write: ask GET status on the NEXT explicit resume.
        final reply=await gateway.execute(bindings.chunk,path:{'id':sessionId},body:form,cancelToken:cancelToken);
        state=_body(reply.data);
        _fileMatches(state,length);
        final confirmed=_integer(state['nextOffsetBytes'],'nextOffsetBytes');
        if(confirmed<=offset || confirmed>next) throw const FormatException('Server offset did not advance consistently');
        offset=confirmed;
        onProgress?.call(_progress(state,length));
      }
    }else{
      final putter=partTransport;
      if(putter==null) throw StateError('R2 uploads need a CloudflareR2PartTransport; never send tokens to signed URLs');
      final upload=state['upload'] as Map;
      final partSize=_integer(upload['chunkSizeBytes'],'chunkSizeBytes');
      if(partSize<5*1024*1024 || partSize>512*1024*1024) throw const FormatException('Invalid Cloudflare R2 part size');
      final count=(length+partSize-1)~/partSize;
      if(count>10000) throw StateError('Too many multipart parts');
      final existing=state['parts'];
      final confirmed=<int>{};
      if(existing is List){
        for(final part in existing){
          if(part is! Map) throw const FormatException('Invalid confirmed upload part');
          final n=_integer(part['partNumber'],'partNumber');
          final offset=(n-1)*partSize;
          if(n<1||n>count||_integer(part['sizeBytes'],'partSize')!=
              ((offset+partSize)>length?length-offset:partSize)) throw const FormatException('Invalid confirmed part size');
          confirmed.add(n);
        }
      }
      for(var n=1;n<=count;n++){
        if(confirmed.contains(n))continue;
        if(cancelToken?.isCancelled??false) throw StateError('Upload cancelled');
        final signed=_body((await gateway.execute(bindings.partUrl,
          path:{'id':sessionId,'partNumber':n},cancelToken:cancelToken)).data);
        final address=signed['url'];
        if(address is! String || address.length>8192) throw const FormatException('Invalid presigned PUT URL');
        final start=(n-1)*partSize;
        final end=start+partSize>length?length:start+partSize;
        if(_integer(signed['expectedSizeBytes'],'expectedSizeBytes')!=end-start) throw const FormatException('Presigned part size differs');
        final url=Uri.tryParse(address);
        if(url==null) throw const FormatException('Invalid signed upload URL');
        final etag=await putter.putPart(url,file,start,end,cancelToken:cancelToken);
        state=_body((await gateway.execute(bindings.partAck,
          path:{'id':sessionId,'partNumber':n},
          body:{'etag':etag,'sizeBytes':end-start},cancelToken:cancelToken)).data);
        onProgress?.call(_progress(state,length));
      }
    }
    // Finalize only after all bytes/parts were acknowledged by the server.
    state=await status(sessionId);
    if(_progress(state,length).uploadedBytes!=length) throw StateError('Upload not fully acknowledged by server');
    return _body((await gateway.execute(bindings.complete,
        path:{'id':sessionId},body:{'parts':<Object>[]},cancelToken:cancelToken)).data);
  }
}
