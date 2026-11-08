import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'application/resumable_upload_workflow.dart';
import 'domain/upload_workflow_port.dart';
import 'media_upload_repository.dart';
import 'media_upload_widget_composition.dart';

/// Compatibility surface for the existing media UI. Upload/checkpoint/identity
/// orchestration lives in ResumableUploadWorkflow (Application) and
/// MediaUploadWorkflowAdapter (Data). No HTTP or storage work in build/State.
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
  /// Legacy callback preserved until the typed completion DTO migration.
  final void Function(Map<String,dynamic> result)? onCompleted;
  @override State<FableResumableUploadCard> createState() =>
      _FableResumableUploadCardState();
}

class _FableResumableUploadCardState extends State<FableResumableUploadCard> {
  late ResumableUploadWorkflow _workflow;
  StreamSubscription<UploadFlowSnapshot>? _stateUpdates;
  StreamSubscription<UploadFlowReceipt>? _receipts;

  bool get _ar=>Localizations.localeOf(context).languageCode=='ar';

  bool _sourceChanged(FableResumableUploadCard old) =>
      !identical(old.file,widget.file) ||
      !identical(old.repository,widget.repository) ||
      !identical(old.checkpoints,widget.checkpoints) ||
      old.checkpoints.scope!=widget.checkpoints.scope ||
      old.kind!=widget.kind || old.mimeType!=widget.mimeType ||
      old.purpose!=widget.purpose || old.visibility!=widget.visibility;

  void _bind() {
    final flow=composeResumableMediaUpload(
      file:widget.file, repository:widget.repository,
      checkpoints:widget.checkpoints, kind:widget.kind,
      mimeType:widget.mimeType, purpose:widget.purpose,
      visibility:widget.visibility,
    );
    _workflow=flow;
    _stateUpdates=flow.changes.listen((_){
      if(mounted && identical(_workflow,flow))setState((){});
    });
    _receipts=flow.completedResults.listen((receipt){
      if(mounted && identical(_workflow,flow)) {
        // Keep the public API byte-for-byte compatible for existing callers.
        // New generated features should depend on typed receipts instead.
        widget.onCompleted?.call(Map<String,dynamic>.from(receipt.legacyResult));
      }
    });
  }

  void _unbind() {
    _workflow.dispose(); // Synchronously fences stale callbacks and tokens.
    unawaited(_stateUpdates?.cancel());
    unawaited(_receipts?.cancel());
    _stateUpdates=null;
    _receipts=null;
  }

  @override void initState() {
    super.initState();
    _bind();
  }

  @override void didUpdateWidget(covariant FableResumableUploadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(_sourceChanged(oldWidget)) {
      _unbind();
      _bind();
    }
  }

  @override void dispose() {
    _unbind();
    super.dispose();
  }

  String? _errorText(UploadFlowProblem? problem) => switch(problem) {
    null => null,
    UploadFlowProblem.missingIdentityEvents =>
      'Verified authentication change events are required for media uploads.',
    UploadFlowProblem.identityChanged =>
      'Account changed. Reopen upload with this account’s verified Backend and checkpoint store.',
    UploadFlowProblem.invalidCheckpoint =>
      'Saved upload cannot be resumed; select the original file.',
    UploadFlowProblem.transferInterrupted => _ar
      ? 'توقف الرفع. افحص الاتصال ثم اختر استئناف؛ لن نعيد إرسال الجزء تلقائيًا.'
      : 'Upload stopped. Check connection and resume; writes are not replayed automatically.',
    UploadFlowProblem.cancellationUnconfirmed => _ar
      ? 'أُوقف الاستئناف المحلي. تعذّر تأكيد الإلغاء في الخادم، راجع الجلسة لاحقًا.'
      : 'Local resume disabled. Backend cancellation could not be confirmed.',
  };

  @override Widget build(BuildContext context) {
    final state=_workflow.snapshot;
    final fraction=((state.progress?.percentage??0).toDouble()/100)
        .clamp(0.0,1.0).toDouble();
    final bytes=state.progress?.confirmedBytes??0;
    final total=state.progress?.totalBytes??0;
    final title=widget.title??(_ar?'رفع الملف':'File upload');
    final error=_errorText(state.problem);
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(title,style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:12),
      Semantics(value:'${(fraction*100).toStringAsFixed(0)}%',child:
        LinearProgressIndicator(value:state.progress==null?0:fraction)),
      const SizedBox(height:8),
      Text(_ar?'المؤكّد على الخادم: $bytes / $total بايت'
        :'Server confirmed: $bytes / $total bytes'),
      if(error!=null)Padding(
        padding:const EdgeInsets.only(top:8),child:Text(error)),
      if(state.completed)Text(_ar?'اكتمل الرفع':'Upload complete'),
      if(state.cancelled)Text(_ar?'أُلغي الرفع':'Upload cancelled'),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        if(!state.busy&&!state.blocked&&!state.cancelled&&!state.completed&&state.checkpoint==null)
          FilledButton(onPressed:()=>unawaited(_workflow.start(resume:false)),
            child:Text(_ar?'بدء الرفع':'Upload')),
        if(!state.busy&&!state.blocked&&!state.cancelled&&!state.completed&&state.checkpoint!=null)
          FilledButton(onPressed:()=>unawaited(_workflow.start(resume:true)),
            child:Text(_ar?'استئناف':'Resume')),
        if(state.busy&&!state.blocked)
          OutlinedButton(onPressed:state.paused?null:_workflow.pause,
            child:Text(_ar?'إيقاف مؤقت':'Pause')),
        if(!state.completed&&!state.cancelled&&!state.blocked)
          TextButton(onPressed:()=>unawaited(_workflow.cancel()),
            child:Text(_ar?'إلغاء':'Cancel')),
      ]),
    ])));
  }
}
