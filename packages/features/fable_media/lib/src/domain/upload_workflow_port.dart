import 'dart:async';

/// Data that may cross the Domain/Application boundary. No File, HTTP,
/// CancelToken, credentials, Fable-specific routes or UI framework.
final class UploadFlowCheckpoint {
  const UploadFlowCheckpoint({
    required this.sessionId,
    required this.sha256,
    required this.sizeBytes,
  });
  final String sessionId;
  final String sha256;
  final int sizeBytes;
}

final class UploadFlowProgress {
  const UploadFlowProgress({
    required this.confirmedBytes,
    required this.totalBytes,
    required this.percentage,
  });
  final int confirmedBytes;
  final int totalBytes;
  final num percentage;
}

/// Compatibility-only payload for the existing public onCompleted callback.
/// The Application never parses or persists this raw response; a later
/// typed DTO migration must replace this final legacy escape hatch.
final class UploadFlowReceipt {
  const UploadFlowReceipt(this.legacyResult);
  final Map<String, Object?> legacyResult;
}

enum UploadFlowProblem {
  missingIdentityEvents,
  identityChanged,
  invalidCheckpoint,
  transferInterrupted,
  cancellationUnconfirmed,
}

final class UploadFlowSnapshot {
  const UploadFlowSnapshot({
    this.checkpoint,
    this.progress,
    this.problem,
    this.busy = false,
    this.paused = false,
    this.cancelled = false,
    this.completed = false,
    this.blocked = false,
  });
  final UploadFlowCheckpoint? checkpoint;
  final UploadFlowProgress? progress;
  final UploadFlowProblem? problem;
  final bool busy, paused, cancelled, completed, blocked;
}

/// A revocable transport operation. Only the Data adapter can hold Dio's token.
abstract interface class UploadFlowCancellation {
  void cancel();
  bool get isCancelled;
}

/// Verified Backend/account scoped upload + checkpoint adapter. Implementations
/// own file hashing, authenticated HTTP, resumable storage and signed R2 PUT.
abstract interface class UploadWorkflowPort {
  /// Null means unavailable Auth revocation events: fail closed in Application.
  Stream<void>? get identityChanges;
  int get currentIdentityRevision;
  bool isSameIdentity(int revision);
  UploadFlowCancellation newCancellation();

  /// Includes original file hash verification before announcing resume.
  Future<UploadFlowCheckpoint?> restoreVerifiedCheckpoint();
  Future<UploadFlowReceipt> upload({
    required bool resume,
    required UploadFlowCheckpoint? checkpoint,
    required UploadFlowCancellation cancellation,
    required bool Function() mayPersist,
    required void Function(UploadFlowCheckpoint) onCheckpoint,
    required void Function(UploadFlowProgress) onProgress,
  });

  Future<void> clearCheckpoint();

  /// MUST clear durable local resume intent BEFORE any remote DELETE.
  /// Do not delete a session under a different authenticated identity.
  Future<void> cancel({required String? sessionId, required int identityRevision});
}
