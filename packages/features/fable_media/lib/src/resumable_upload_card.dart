import 'dart:io';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'media_upload_repository.dart';

/// Reusable OPTIONAL Media widget. Domain pages supply a selected File and a
/// contract-verified repository. No Social/Bookings/Store assumptions.
/// A pause only cancels in-flight transport; it does NOT abort the server session.
/// Cancel permanently clears the local resume intent before calling DELETE.
class FableResumableUploadCard extends StatefulWidget {
  const FableResumableUploadCard({super.key, required this.file,
    required this.repository, required this.checkpoints, required this.kind,
    required this.mimeType, this.title, this.purpose, this.visibility='PRIVATE',
    this.onCompleted});
  final File file;
  final MediaUploadRepository repository;
  final MediaUploadCheckpointStore checkpoints;
  final String kind, mimeType, visibility;
  final String? title, purpose;
  final void Function(Map<String,dynamic> result)? onCompleted;
  @override State<FableResumableUploadCard> createState()=>_FableResumableUploadCardState();
}

class _FableResumableUploadCardState extends State<FableResumableUploadCard> {
  CancelToken? _cancelToken;
  MediaUploadCheckpoint? _checkpoint;
  MediaUploadProgress? _progress;
  bool _busy=false, _stopped=false, _cancelled=false;
  String? _error;
  bool _completed=false;
  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';

  @override void initState(){super.initState();_restore();}
  Future<void> _restore() async {
    try {final p=await widget.checkpoints.read();
      if(!mounted||_cancelled)return;
      if(p!=null){await p.verify(widget.file);if(mounted)setState(()=>_checkpoint=p);}
    }catch(_){if(mounted)setState(()=>_error='Saved upload cannot be resumed; select the original file.');}
  }
  Future<void> _run({required bool resume}) async {
    if(_busy||_cancelled||_completed)return;
    final checkpoint=_checkpoint;
    if(resume&&checkpoint==null)return;
    _stopped=false;
    final token=CancelToken();_cancelToken=token;
    setState((){_busy=true;_error=null;});
    try{
      final result=resume
        ?await widget.repository.resume(widget.file,checkpoint!,cancelToken:token,
          onProgress:(p){if(mounted&&!_cancelled)setState(()=>_progress=p);})
        :await widget.repository.start(widget.file,kind:widget.kind,mimeType:widget.mimeType,
          purpose:widget.purpose,visibility:widget.visibility,cancelToken:token,
          saveCheckpoint:(p)async{
            if(_cancelled)throw StateError('Upload cancelled');
            await widget.checkpoints.save(p);
            if(_cancelled){await widget.checkpoints.clear();throw StateError('Upload cancelled');}
            if(mounted)setState(()=>_checkpoint=p);
          },onProgress:(p){if(mounted&&!_cancelled)setState(()=>_progress=p);});
      if(!_cancelled){await widget.checkpoints.clear();
        if(mounted)setState((){_checkpoint=null;_completed=true;});
        widget.onCompleted?.call(result);
      }
    }catch(_){
      if(mounted&&!_cancelled&&!_stopped){setState(()=>_error=_ar
        ?'توقف الرفع. افحص الاتصال ثم اختر استئناف؛ لن نعيد إرسال الجزء تلقائيًا.'
        :'Upload stopped. Check connection and resume; writes are not replayed automatically.');}
    }finally{if(mounted)setState(()=>_busy=false);_cancelToken=null;}
  }
  void _pause(){if(!_busy||_cancelToken==null)return;_stopped=true;
    _cancelToken!.cancel('Paused by user');setState((){});}
  Future<void> _cancel()async{
    if(_cancelled||_completed)return;
    _cancelled=true;_stopped=true;_cancelToken?.cancel('Cancelled by user');
    final session=_checkpoint?.sessionId;
    try{
      // The durable local intent is cleared FIRST, regardless of network state.
      await widget.checkpoints.clear();
      if(session!=null)await widget.repository.cancel(session,
        persistCancelIntent:(_) => widget.checkpoints.clear());
    }catch(_){if(mounted)setState(()=>_error=_ar
      ?'أُوقف الاستئناف المحلي. تعذّر تأكيد الإلغاء في الخادم، راجع الجلسة لاحقًا.'
      :'Local resume disabled. Backend cancellation could not be confirmed.');}
    finally{if(mounted)setState((){_checkpoint=null;_busy=false;});}
  }
  @override void dispose(){_cancelToken?.cancel('Widget disposed');super.dispose();}
  @override Widget build(BuildContext context){
    final fraction=((_progress?.percentage??0).toDouble()/100).clamp(0.0,1.0).toDouble();
    final bytes=_progress?.uploadedBytes??0,total=_progress?.totalBytes??0;
    final title=widget.title??(_ar?'رفع الملف':'File upload');
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(title,style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:12),
      Semantics(value:'${(fraction*100).toStringAsFixed(0)}%',child:
        LinearProgressIndicator(value:_progress==null?0:fraction)),
      const SizedBox(height:8),
      Text(_ar?'المؤكّد على الخادم: $bytes / $total بايت':'Server confirmed: $bytes / $total bytes'),
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_error!)),
      if(_completed)Text(_ar?'اكتمل الرفع':'Upload complete'),
      if(_cancelled)Text(_ar?'أُلغي الرفع':'Upload cancelled'),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        if(!_busy&&!_cancelled&&!_completed&&_checkpoint==null)
          FilledButton(onPressed:()=>_run(resume:false),child:Text(_ar?'بدء الرفع':'Upload')),
        if(!_busy&&!_cancelled&&!_completed&&_checkpoint!=null)
          FilledButton(onPressed:()=>_run(resume:true),child:Text(_ar?'استئناف':'Resume')),
        if(_busy)OutlinedButton(onPressed:_stopped?null:_pause,child:Text(_ar?'إيقاف مؤقت':'Pause')),
        if(!_completed&&!_cancelled)TextButton(onPressed:_cancel,child:Text(_ar?'إلغاء':'Cancel')),
      ]),
    ])));
  }
}
