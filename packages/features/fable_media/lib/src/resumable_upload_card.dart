import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fable_core/fable_core.dart';
import 'media_upload_repository.dart';

/// Optional contract-bound media widget. Its repository supplies the same
/// verified Auth epoch/events used for network calls. Other Backend MUST wire
/// those events independently: no guessed Fable auth namespace.
/// Pause cancels transport only; Cancel clears resume intent before DELETE.
class FableResumableUploadCard extends StatefulWidget {
  const FableResumableUploadCard({super.key, required this.file,
    required this.repository, required this.checkpoints, required this.kind,
    required this.mimeType, this.title, this.purpose, this.visibility='PRIVATE',
    this.onCompleted});
  final File file;
  final MediaUploadRepository repository;
  final MediaUploadCheckpointStore checkpoints;
  final String kind,mimeType,visibility;
  final String? title,purpose;
  final void Function(Map<String,dynamic> result)? onCompleted;
  @override State<FableResumableUploadCard> createState()=>_FableResumableUploadCardState();
}

class _FableResumableUploadCardState extends State<FableResumableUploadCard> {
  CancelToken? _cancelToken;
  StreamSubscription<FableIdentityEvent>? _identityChanges;
  MediaUploadCheckpoint? _checkpoint;
  MediaUploadProgress? _progress;
  int _generation=0;
  int? _boundIdentity;
  bool _busy=false,_stopped=false,_cancelled=false,_completed=false;
  bool _identityBlocked=false;
  String? _error;

  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';
  bool _active(int generation) =>
    mounted && !_identityBlocked && generation==_generation &&
    _boundIdentity!=null &&
    widget.repository.isSameIdentity(_boundIdentity!);

  void _clearTransient({required bool block}){
    // Invalidate callbacks and cancel any old-user HTTP/R2 work immediately.
    _generation++;
    _cancelToken?.cancel('Media upload context changed');
    _cancelToken=null;
    _checkpoint=null;
    _progress=null;
    _busy=false;
    _stopped=false;
    _cancelled=false;
    _completed=false;
    _boundIdentity=null;
    _identityBlocked=block;
    _error=block
      ? 'Account changed. Reopen upload with this account’s verified Backend and checkpoint store.'
      : null;
  }

  void _bind(){
    final events=widget.repository.identityEvents;
    if(events==null){
      // A secure repository alone is insufficient to revoke UI callbacks
      // on an asynchronous login/logout. Fail closed for this widget.
      _identityBlocked=true;
      _error='Verified authentication change events are required for media uploads.';
      return;
    }
    final initial=widget.repository.currentIdentityRevision;
    _boundIdentity=initial;
    _identityChanges=events.listen((_){
      if(!mounted)return;
      setState(()=>_clearTransient(block:true));
    });
    if(!widget.repository.isSameIdentity(initial)){
      _clearTransient(block:true);
    }
  }

  bool _sourceChanged(FableResumableUploadCard old){
    return !identical(old.file,widget.file) ||
      !identical(old.repository,widget.repository) ||
      !identical(old.checkpoints,widget.checkpoints) ||
      old.checkpoints.scope!=widget.checkpoints.scope ||
      old.kind!=widget.kind || old.mimeType!=widget.mimeType ||
      old.purpose!=widget.purpose || old.visibility!=widget.visibility;
  }

  @override void initState(){
    super.initState();
    _bind();
    if(!_identityBlocked)unawaited(_restore());
  }

  @override void didUpdateWidget(covariant FableResumableUploadCard oldWidget){
    super.didUpdateWidget(oldWidget);
    if(_sourceChanged(oldWidget)){
      unawaited(_identityChanges?.cancel());
      _identityChanges=null;
      _clearTransient(block:false);
      _bind();
      if(!_identityBlocked)unawaited(_restore());
    }else if(!_identityBlocked && _boundIdentity!=null &&
        !widget.repository.isSameIdentity(_boundIdentity!)){
      _clearTransient(block:true);
    }
  }

  Future<void> _restore()async{
    final generation=_generation;
    final file=widget.file;
    final store=widget.checkpoints;
    try{
      final found=await store.read();
      if(!_active(generation))return;
      if(found!=null){
        await found.verify(file);
        if(_active(generation))setState(()=>_checkpoint=found);
      }
    }catch(_){
      if(_active(generation)){
        setState(()=>_error='Saved upload cannot be resumed; select the original file.');
      }
    }
  }

  Future<void> _run({required bool resume})async{
    if(_busy||_cancelled||_completed||_identityBlocked)return;
    final checkpoint=_checkpoint;
    if(resume&&checkpoint==null)return;
    final generation=_generation;
    if(!_active(generation))return;
    final repository=widget.repository;
    final file=widget.file;
    final store=widget.checkpoints;
    final kind=widget.kind,mimeType=widget.mimeType;
    final purpose=widget.purpose,visibility=widget.visibility;
    final token=CancelToken();
    _cancelToken=token;
    _stopped=false;
    setState((){_busy=true;_error=null;});
    void progress(MediaUploadProgress p){
      if(_active(generation)&&!_cancelled&&!_stopped){
        setState(()=>_progress=p);
      }
    }
    try{
      final result=resume
        ?await repository.resume(file,checkpoint!,cancelToken:token,
          onProgress:progress)
        :await repository.start(file,kind:kind,mimeType:mimeType,
          purpose:purpose,visibility:visibility,cancelToken:token,
          saveCheckpoint:(next)async{
            if(!_active(generation)||_cancelled||_stopped){
              throw StateError('Old upload context discarded');
            }
            await store.save(next);
            // Never restore an old checkpoint into the new account's widget.
            if(!_active(generation)||_cancelled||_stopped){
              throw StateError('Old upload context discarded');
            }
            setState(()=>_checkpoint=next);
          },onProgress:progress);
      if(!_active(generation)||_cancelled||_stopped)return;
      // Captured account-scoped store, never widget.checkpoints from user B.
      await store.clear();
      if(!_active(generation)||_cancelled||_stopped)return;
      setState((){_checkpoint=null;_completed=true;});
      widget.onCompleted?.call(result);
    }catch(_){
      if(_active(generation)&&!_cancelled&&!_stopped){
        setState(()=>_error=_ar
          ?'توقف الرفع. افحص الاتصال ثم اختر استئناف؛ لن نعيد إرسال الجزء تلقائيًا.'
          :'Upload stopped. Check connection and resume; writes are not replayed automatically.');
      }
    }finally{
      if(_active(generation)){
        setState(()=>_busy=false);
        if(identical(_cancelToken,token))_cancelToken=null;
      }
    }
  }

  void _pause(){
    if(!_busy||_cancelToken==null)return;
    _stopped=true;
    _cancelToken!.cancel('Paused by user');
    setState((){});
  }

  Future<void> _cancel()async{
    if(_cancelled||_completed||_identityBlocked)return;
    final store=widget.checkpoints;
    final repository=widget.repository;
    final identity=_boundIdentity;
    final sessionId=_checkpoint?.sessionId;
    final token=_cancelToken;
    final generation=++_generation; // Old _run and _restore may not update UI.
    _cancelled=true;
    _stopped=true;
    token?.cancel('Cancelled by user');
    setState((){});
    try{
      await store.clear(); // Durable cancel intent FIRST, even if DELETE fails.
      if(sessionId!=null && identity!=null &&
          repository.isSameIdentity(identity)){
        await repository.cancel(sessionId,
          persistCancelIntent:(_)=>store.clear());
      }
    }catch(_){
      if(mounted && generation==_generation){
        setState(()=>_error=_ar
          ?'أُوقف الاستئناف المحلي. تعذّر تأكيد الإلغاء في الخادم، راجع الجلسة لاحقًا.'
          :'Local resume disabled. Backend cancellation could not be confirmed.');
      }
    }finally{
      if(mounted && generation==_generation){
        setState((){
          _checkpoint=null;
          _busy=false;
          if(identical(_cancelToken,token))_cancelToken=null;
        });
      }
    }
  }

  @override void dispose(){
    _generation++;
    _cancelToken?.cancel('Widget disposed');
    unawaited(_identityChanges?.cancel());
    super.dispose();
  }

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
        if(!_busy&&!_identityBlocked&&!_cancelled&&!_completed&&_checkpoint==null)
          FilledButton(onPressed:()=>_run(resume:false),child:Text(_ar?'بدء الرفع':'Upload')),
        if(!_busy&&!_identityBlocked&&!_cancelled&&!_completed&&_checkpoint!=null)
          FilledButton(onPressed:()=>_run(resume:true),child:Text(_ar?'استئناف':'Resume')),
        if(_busy&&!_identityBlocked)
          OutlinedButton(onPressed:_stopped?null:_pause,child:Text(_ar?'إيقاف مؤقت':'Pause')),
        if(!_completed&&!_cancelled&&!_identityBlocked)
          TextButton(onPressed:_cancel,child:Text(_ar?'إلغاء':'Cancel')),
      ]),
    ])));
  }
}
