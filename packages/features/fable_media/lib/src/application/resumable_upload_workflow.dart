import 'dart:async';
import '../domain/upload_workflow_port.dart';

/// RC125: upload lifecycle and checkpoint orchestration is independent of
/// Flutter widgets, Dio, file system, Fable/Other Backend and presentation.
final class ResumableUploadWorkflow {
  ResumableUploadWorkflow(this._port) {
    final events = _port.identityChanges;
    if (events == null) {
      _blocked = true;
      _problem = UploadFlowProblem.missingIdentityEvents;
      _publish();
      return;
    }
    _identityRevision = _port.currentIdentityRevision;
    _identitySubscription = events.listen((_) => _invalidateAccount());
    if (!_port.isSameIdentity(_identityRevision!)) {
      _invalidateAccount();
    } else {
      unawaited(restore());
    }
  }

  final UploadWorkflowPort _port;
  final _states = StreamController<UploadFlowSnapshot>.broadcast(sync: true);
  final _completions = StreamController<UploadFlowReceipt>.broadcast(sync: true);
  Stream<UploadFlowSnapshot> get changes => _states.stream;
  Stream<UploadFlowReceipt> get completedResults => _completions.stream;
  StreamSubscription<void>? _identitySubscription;
  UploadFlowCancellation? _cancellation;
  UploadFlowCheckpoint? _checkpoint;
  UploadFlowProgress? _progress;
  UploadFlowProblem? _problem;
  int? _identityRevision;
  int _generation = 0;
  bool _busy = false;
  bool _paused = false;
  bool _cancelled = false;
  bool _completed = false;
  bool _blocked = false;
  bool _disposed = false;

  UploadFlowSnapshot get snapshot => UploadFlowSnapshot(
    checkpoint: _checkpoint,
    progress: _progress,
    problem: _problem,
    busy: _busy,
    paused: _paused,
    cancelled: _cancelled,
    completed: _completed,
    blocked: _blocked,
  );

  bool _active(int revision) => !_disposed && !_blocked &&
      _identityRevision != null && revision == _generation &&
      _port.isSameIdentity(_identityRevision!);

  void _publish() {
    if (!_disposed) _states.add(snapshot);
  }

  void _invalidateAccount() {
    if (_disposed) return;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _checkpoint = null;
    _progress = null;
    _identityRevision = null;
    _busy = false;
    _paused = false;
    _cancelled = false;
    _completed = false;
    _blocked = true;
    _problem = UploadFlowProblem.identityChanged;
    _publish();
  }

  Future<void> restore() async {
    if (_disposed || _blocked || _cancelled || _completed) return;
    final generation = _generation;
    try {
      final checkpoint = await _port.restoreVerifiedCheckpoint();
      if (_active(generation) && checkpoint != null) {
        _checkpoint = checkpoint;
        _publish();
      }
    } catch (_) {
      if (_active(generation)) {
        _problem = UploadFlowProblem.invalidCheckpoint;
        _publish();
      }
    }
  }

  Future<void> start({required bool resume}) async {
    if (_busy || _cancelled || _completed || _blocked || _disposed) return;
    final checkpoint = _checkpoint;
    if (resume && checkpoint == null) return;
    // New user action wins over any async checkpoint restore still pending.
    // A delayed restore is never allowed to overwrite an active upload.
    final generation = ++_generation;
    if (!_active(generation)) return;
    final cancellation = _port.newCancellation();
    _cancellation = cancellation;
    _paused = false;
    _busy = true;
    _problem = null;
    _publish();

    bool canApply() => _active(generation) && !_cancelled &&
        !_paused && !cancellation.isCancelled;

    try {
      final receipt = await _port.upload(
        resume: resume,
        checkpoint: checkpoint,
        cancellation: cancellation,
        mayPersist: canApply,
        onCheckpoint: (checkpoint) {
          if (!canApply()) return;
          _checkpoint = checkpoint;
          _publish();
        },
        onProgress: (progress) {
          if (!canApply()) return;
          _progress = progress;
          _publish();
        },
      );
      if (!canApply()) return;
      await _port.clearCheckpoint();
      if (!canApply()) return;
      _checkpoint = null;
      _completed = true;
      _publish();
      // Same synchronous event behavior as the legacy onCompleted callback.
      _completions.add(receipt);
    } catch (_) {
      if (canApply()) {
        _problem = UploadFlowProblem.transferInterrupted;
        _publish();
      }
    } finally {
      if (_active(generation)) {
        _busy = false;
        if (identical(_cancellation, cancellation)) _cancellation = null;
        _publish();
      }
    }
  }

  void pause() {
    if (_disposed || _blocked || !_busy || _cancellation == null) return;
    _paused = true;
    _cancellation!.cancel();
    _publish();
  }

  Future<void> cancel() async {
    if (_disposed || _blocked || _cancelled || _completed) return;
    final identityRevision = _identityRevision;
    if (identityRevision == null || !_port.isSameIdentity(identityRevision)) {
      _invalidateAccount();
      return;
    }
    final sessionId = _checkpoint?.sessionId;
    final generation = ++_generation;
    _cancelled = true;
    _paused = true;
    _cancellation?.cancel();
    _publish();
    try {
      await _port.cancel(
        sessionId: sessionId, identityRevision: identityRevision);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _problem = UploadFlowProblem.cancellationUnconfirmed;
        _publish();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _checkpoint = null;
        _busy = false;
        _cancellation = null;
        _publish();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    unawaited(_identitySubscription?.cancel());
    unawaited(_states.close());
    unawaited(_completions.close());
  }
}
