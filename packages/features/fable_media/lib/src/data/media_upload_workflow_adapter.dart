import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../domain/upload_workflow_port.dart';
import '../media_upload_repository.dart';

final class _DioUploadCancellation implements UploadFlowCancellation {
  final token = CancelToken();
  @override bool get isCancelled => token.isCancelled;
  @override void cancel() => token.cancel('Media upload flow invalidated');
}

/// Fable/Other-specific transport stays in Data. Uses precisely the existing
/// verified repository/operation bindings; no new endpoints or URLs are added.
/// Local checkpoint storage is already backend/account scoped by its hash.
final class MediaUploadWorkflowAdapter implements UploadWorkflowPort {
  const MediaUploadWorkflowAdapter({
    required this.file,
    required this.repository,
    required this.checkpoints,
    required this.kind,
    required this.mimeType,
    required this.visibility,
    this.purpose,
  });

  final File file;
  final MediaUploadRepository repository;
  final MediaUploadCheckpointStore checkpoints;
  final String kind, mimeType, visibility;
  final String? purpose;

  @override
  Stream<void>? get identityChanges =>
      repository.identityEvents?.map<void>((_) {});
  @override int get currentIdentityRevision => repository.currentIdentityRevision;
  @override bool isSameIdentity(int revision) =>
      repository.isSameIdentity(revision);
  @override UploadFlowCancellation newCancellation() => _DioUploadCancellation();

  UploadFlowCheckpoint _checkpoint(MediaUploadCheckpoint value) =>
      UploadFlowCheckpoint(sessionId: value.sessionId,
          sha256: value.sha256, sizeBytes: value.sizeBytes);

  MediaUploadCheckpoint _stored(UploadFlowCheckpoint value) =>
      MediaUploadCheckpoint(sessionId: value.sessionId,
          sha256: value.sha256, sizeBytes: value.sizeBytes);

  @override
  Future<UploadFlowCheckpoint?> restoreVerifiedCheckpoint() async {
    final stored = await checkpoints.read();
    if (stored == null) return null;
    await stored.verify(file);
    return _checkpoint(stored);
  }

  @override
  Future<UploadFlowReceipt> upload({
    required bool resume,
    required UploadFlowCheckpoint? checkpoint,
    required UploadFlowCancellation cancellation,
    required bool Function() mayPersist,
    required void Function(UploadFlowCheckpoint) onCheckpoint,
    required void Function(UploadFlowProgress) onProgress,
  }) async {
    if (cancellation is! _DioUploadCancellation) {
      throw StateError('Upload transport cancellation mismatch');
    }
    void progress(MediaUploadProgress p) {
      if (!mayPersist()) return;
      onProgress(UploadFlowProgress(
        confirmedBytes: p.uploadedBytes,
        totalBytes: p.totalBytes, percentage: p.percentage));
    }

    final Map<String, dynamic> result;
    if (resume) {
      if (checkpoint == null) throw StateError('Missing verified checkpoint');
      result = await repository.resume(file, _stored(checkpoint),
        cancelToken: cancellation.token, onProgress: progress);
    } else {
      result = await repository.start(file,
        kind: kind, mimeType: mimeType, purpose: purpose,
        visibility: visibility, cancelToken: cancellation.token,
        onProgress: progress,
        saveCheckpoint: (next) async {
          // Never persist a checkpoint from an old account/cancelled operation.
          if (!mayPersist()) throw StateError('Old upload context discarded');
          await checkpoints.save(next);
          if (!mayPersist()) throw StateError('Old upload context discarded');
          onCheckpoint(_checkpoint(next));
        });
    }
    if (!mayPersist()) throw StateError('Old upload context discarded');
    // Preserve the existing public onCompleted payload without leaking it
    // into upload lifecycle state or persisting signed storage credentials.
    return UploadFlowReceipt(Map<String, Object?>.from(result));
  }

  @override Future<void> clearCheckpoint() => checkpoints.clear();

  @override
  Future<void> cancel({
    required String? sessionId,
    required int identityRevision,
  }) async {
    // Ordering is security-critical: disable durable resume FIRST, even if
    // the server DELETE later fails or the authenticated account changes.
    await checkpoints.clear();
    if (sessionId != null && repository.isSameIdentity(identityRevision)) {
      await repository.cancel(sessionId,
        persistCancelIntent: (_) => checkpoints.clear());
    }
  }
}
