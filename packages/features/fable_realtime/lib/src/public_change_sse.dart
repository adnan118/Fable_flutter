import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'public_change_sync.dart';

/// Optional best-effort SSE delivery for PUBLIC revision hints only.
/// SSE is never an authoritative price source and never supplies protected data.
/// Missing hints after process death/network loss are repaired by snapshot GET.
/// No Bearer token, cookie or Fable device identity is sent to this stream.
class PublicRevisionSse {
  PublicRevisionSse({required Uri origin,required OperationCatalog catalog,
    required String streamOperationId,required this.onHint,Dio? client}):
      _origin=origin,_path=_verifiedPath(catalog,streamOperationId),
      _dio=client??Dio(BaseOptions(connectTimeout:const Duration(seconds:8),
        receiveTimeout:Duration.zero,followRedirects:false,
        responseType:ResponseType.stream)) {
    final local=origin.scheme=='http'&&const {'localhost','127.0.0.1','10.0.2.2','::1'}.contains(origin.host);
    if(!(origin.scheme=='https'||local)||!origin.hasAuthority||origin.userInfo.isNotEmpty||
      origin.hasQuery||origin.hasFragment||(origin.path.isNotEmpty&&origin.path!='/')){
      throw ArgumentError('SSE requires a trusted bare backend origin');
    }
    if(_dio.options.headers.isNotEmpty){
      throw ArgumentError('Public SSE transport must not carry ambient headers or identifiers');
    }
  }
  final Uri _origin;
  final String _path;
  final Dio _dio;
  final Future<void> Function(String revision) onHint;
  CancelToken? _cancel;
  bool _running=false;
  static final _rev=RegExp(r'^[a-f0-9]{64}$');
  static String _verifiedPath(OperationCatalog catalog,String id){
    final op=catalog.require(id);
    if(op.method.toUpperCase()!='GET'||op.requiresAuth||
       !op.path.startsWith('/')||op.path.startsWith('//')||
       op.path.contains('..')||op.path.contains('%')||
       op.path.contains('?')||op.path.contains('#')||op.path.contains('{')){
      throw ArgumentError('A declared public GET SSE route is required');
    }
    return op.path;
  }
  /// Call from an app-level lifecycle coordinator. The normal snapshot watcher
  /// remains active even if proxies/devices do not support SSE streaming.
  Future<void> connect() async {
    if(_running)return;
    _running=true;
    final cancel=CancelToken();_cancel=cancel;
    try{
      final response=await _dio.getUri<ResponseBody>(_origin.resolve(_path),
        cancelToken:cancel,options:Options(responseType:ResponseType.stream,
          followRedirects:false,headers:{'Accept':'text/event-stream'},
          validateStatus:(s)=>s==200));
      final body=response.data;
      if(body==null)throw const FormatException('SSE empty response');
      String? kind;
      await for(final line in body.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())){
        if(cancel.isCancelled)break;
        if(line.length>2048)throw const FormatException('Oversized SSE line');
        if(line.isEmpty){kind=null;continue;}
        if(line.startsWith('event:')){kind=line.substring(6).trim();continue;}
        if(kind=='content-revision'&&line.startsWith('data:')){
          final data=jsonDecode(line.substring(5));
          if(data is Map&&data['revision'] is String&&_rev.hasMatch(data['revision'] as String)){
            await onHint(data['revision'] as String);
          }
        }
      }
    }finally{_running=false;if(identical(_cancel,cancel))_cancel=null;}
  }
  void stop(){_cancel?.cancel('paused');_cancel=null;}
  void dispose(){stop();_dio.close(force:true);}
}

/// Prevent redundant snapshot calls on every duplicate SSE hint.
class PublicSseRevalidator {
  PublicSseRevalidator(this.sync);
  final PublicChangeSync sync;
  String? _lastApplied;
  Future<void> _queue=Future<void>.value();
  Future<void> onHint(String revision){
    // لا نعتمد إشارة فشلت شبكتها؛ ونسلسل الإشارات كي لا تُحجب آخر نسخة.
    final attempt=_queue.then((_)async{
      if(revision==_lastApplied)return;
      try{
        await sync.onResume();
        _lastApplied=revision;
      }catch(_){
        // A later identical hint must retry rather than being discarded forever.
      }
    });
    _queue=attempt;
    return attempt;
  }
}
