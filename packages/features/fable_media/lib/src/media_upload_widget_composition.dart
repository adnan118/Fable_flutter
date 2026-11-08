import 'dart:io';
import 'application/resumable_upload_workflow.dart';
import 'data/media_upload_workflow_adapter.dart';
import 'media_upload_repository.dart';

/// Legacy constructor boundary. Backend-specific adapters are chosen here,
/// OUTSIDE the widget and independent of its display logic.
ResumableUploadWorkflow composeResumableMediaUpload({
  required File file,
  required MediaUploadRepository repository,
  required MediaUploadCheckpointStore checkpoints,
  required String kind,
  required String mimeType,
  required String visibility,
  String? purpose,
}) => ResumableUploadWorkflow(MediaUploadWorkflowAdapter(
  file: file,
  repository: repository,
  checkpoints: checkpoints,
  kind: kind,
  mimeType: mimeType,
  visibility: visibility,
  purpose: purpose,
));
