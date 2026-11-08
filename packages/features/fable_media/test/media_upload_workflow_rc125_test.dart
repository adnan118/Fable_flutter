import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

const _checkpoint = UploadFlowCheckpoint(
  sessionId: '123e4567-e89b-42d3-a456-426614174000',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  sizeBytes: 100,
);

final class _StopHandle implements UploadFlowCancellation {
  bool cancelled = false;
  @override bool get isCancelled => cancelled;
  @override void cancel() { cancelled = true; }
}

final class _Port implements UploadWorkflowPort {
  final events = StreamController<void>.broadcast(sync: true);
  bool withEvents = true;
  bool active = true;
  int revision = 1;
  int uploads = 0;
  int aborts = 0;
  int clearCount = 0;
  int restores = 0;
  bool restoreFails = false;
  bool abortFails = false;
  UploadFlowCheckpoint? checkpoint;
  Completer<UploadFlowCheckpoint?>? delayedRestore;
  Completer<UploadFlowReceipt>? pendingUpload;
  Completer<void>? pendingClear;
  Completer<void>? pendingAbort;
  void Function(UploadFlowCheckpoint)? checkpointCallback;
  void Function(UploadFlowProgress)? progressCallback;
  bool Function()? mayPersist;
  _StopHandle? handle;
  final calls = <String>[];

  @override Stream<void>? get identityChanges => withEvents ? events.stream : null;
  @override int get currentIdentityRevision => revision;
  @override bool isSameIdentity(int v) => active && v == revision;
  @override UploadFlowCancellation newCancellation() => handle = _StopHandle();

  @override
  Future<UploadFlowCheckpoint?> restoreVerifiedCheckpoint() async {
    restores++;
    if (restoreFails) throw StateError('unusable');
    if (delayedRestore != null) return delayedRestore!.future;
    return checkpoint;
  }

  @override Future<UploadFlowReceipt> upload({
    required bool resume,
    required UploadFlowCheckpoint? checkpoint,
    required UploadFlowCancellation cancellation,
    required bool Function() mayPersist,
    required void Function(UploadFlowCheckpoint) onCheckpoint,
    required void Function(UploadFlowProgress) onProgress,
  }) {
    uploads++;
    calls.add(resume ? 'resume' : 'start');
    checkpointCallback = onCheckpoint;
    progressCallback = onProgress;
    this.mayPersist = mayPersist;
    return pendingUpload!.future;
  }

  @override Future<void> clearCheckpoint() async {
    clearCount++;
    calls.add('clear');
    if (pendingClear != null) await pendingClear!.future;
  }

  @override
  Future<void> cancel({
    required String? sessionId,
    required int identityRevision,
  }) async {
    aborts++;
    calls.add('persistCancel');
    if (sessionId != null && isSameIdentity(identityRevision)) {
      calls.add('backendDelete');
    }
    if (pendingAbort != null) await pendingAbort!.future;
    if (abortFails) throw StateError('Backend DELETE failed');
  }

  void revoke() {
    active = false;
    revision++;
    events.add(null);
  }

  Future<void> close() => events.close();
}

UploadFlowReceipt get _receipt =>
    const UploadFlowReceipt(<String, Object?>{'status': 'COMPLETED'});

void main() {
  test('RC125 without verified identity events cannot restore or upload', () async {
    final port = _Port()..withEvents = false;
    final flow = ResumableUploadWorkflow(port);
    expect(flow.snapshot.blocked, isTrue);
    expect(flow.snapshot.problem, UploadFlowProblem.missingIdentityEvents);
    await flow.start(resume: false);
    expect(port.uploads, 0);
    expect(port.restores, 0);
    flow.dispose();
    await port.close();
  });

  test('RC125 revocation cancels in-flight work and fences late completion', () async {
    final port = _Port()..pendingUpload = Completer<UploadFlowReceipt>();
    final flow = ResumableUploadWorkflow(port);
    final completions = <UploadFlowReceipt>[];
    final sub = flow.completedResults.listen(completions.add);
    await flow.start(resume: true); // No checkpoint, no upload.
    expect(port.uploads, 0);
    final running = flow.start(resume: false);
    await Future<void>.delayed(Duration.zero);
    expect(flow.snapshot.busy, isTrue);
    expect(port.uploads, 1);
    port.progressCallback!(const UploadFlowProgress(
      confirmedBytes: 8, totalBytes: 100, percentage: 8));
    expect(flow.snapshot.progress?.confirmedBytes, 8);
    port.revoke();
    expect(flow.snapshot.blocked, isTrue);
    expect(flow.snapshot.problem, UploadFlowProblem.identityChanged);
    expect(port.handle!.isCancelled, isTrue);
    port.checkpointCallback!(_checkpoint);
    port.progressCallback!(const UploadFlowProgress(
      confirmedBytes: 99, totalBytes: 100, percentage: 99));
    port.pendingUpload!.complete(_receipt);
    await running;
    expect(flow.snapshot.checkpoint, isNull);
    expect(flow.snapshot.progress, isNull);
    expect(port.clearCount, 0);
    expect(completions, isEmpty);
    await sub.cancel();
    flow.dispose();
    await port.close();
  });

  test('RC125 stale restore cannot republish checkpoint after revocation',
      () async {
    final port = _Port()
      ..delayedRestore = Completer<UploadFlowCheckpoint?>();
    final flow = ResumableUploadWorkflow(port);
    await Future<void>.delayed(Duration.zero);
    expect(port.restores, 1);
    port.revoke();
    port.delayedRestore!.complete(_checkpoint);
    await Future<void>.delayed(Duration.zero);
    expect(flow.snapshot.checkpoint, isNull);
    expect(flow.snapshot.blocked, isTrue);
    flow.dispose();
    await port.close();
  });

  test('RC125 pause stops transport; stale completion never becomes success',
      () async {
    final port = _Port()..pendingUpload = Completer<UploadFlowReceipt>();
    final flow = ResumableUploadWorkflow(port);
    final result = flow.start(resume: false);
    await Future<void>.delayed(Duration.zero);
    flow.pause();
    expect(flow.snapshot.paused, isTrue);
    expect(port.handle!.isCancelled, isTrue);
    port.pendingUpload!.complete(_receipt);
    await result;
    expect(flow.snapshot.completed, isFalse);
    expect(flow.snapshot.busy, isFalse);
    expect(port.clearCount, 0);
    flow.dispose();
    await port.close();
  });

  test('RC125 checkpoint restore supports resume, then clear before callback',
      () async {
    final port = _Port()
      ..checkpoint = _checkpoint
      ..pendingUpload = Completer<UploadFlowReceipt>();
    final flow = ResumableUploadWorkflow(port);
    final completions = <UploadFlowReceipt>[];
    final sub = flow.completedResults.listen((receipt) {
      expect(port.calls.last, 'clear');
      completions.add(receipt);
    });
    await Future<void>.delayed(Duration.zero);
    expect(flow.snapshot.checkpoint?.sessionId, _checkpoint.sessionId);
    final running = flow.start(resume: true);
    await Future<void>.delayed(Duration.zero);
    expect(port.calls.first, 'resume');
    port.pendingUpload!.complete(_receipt);
    await running;
    expect(flow.snapshot.completed, isTrue);
    expect(flow.snapshot.checkpoint, isNull);
    expect(port.clearCount, 1);
    expect(completions.single.legacyResult['status'], 'COMPLETED');
    await sub.cancel();
    flow.dispose();
    await port.close();
  });

  test('RC125 cancel starts durable local intent before backend DELETE',
      () async {
    final port = _Port()
      ..checkpoint = _checkpoint
      ..abortFails = true;
    final flow = ResumableUploadWorkflow(port);
    await Future<void>.delayed(Duration.zero);
    await flow.cancel();
    expect(port.calls, ['persistCancel', 'backendDelete']);
    expect(flow.snapshot.cancelled, isTrue);
    expect(flow.snapshot.checkpoint, isNull);
    expect(flow.snapshot.problem, UploadFlowProblem.cancellationUnconfirmed);
    flow.dispose();
    await port.close();
  });

  test('RC125 late clear is fenced and cannot publish completion',
      () async {
    final port = _Port()
      ..pendingUpload = Completer<UploadFlowReceipt>()
      ..pendingClear = Completer<void>();
    final flow = ResumableUploadWorkflow(port);
    final seen = <UploadFlowReceipt>[];
    final sub = flow.completedResults.listen(seen.add);
    final running = flow.start(resume: false);
    await Future<void>.delayed(Duration.zero);
    port.pendingUpload!.complete(_receipt);
    await Future<void>.delayed(Duration.zero);
    expect(port.clearCount, 1);
    port.revoke();
    port.pendingClear!.complete();
    await running;
    expect(flow.snapshot.completed, isFalse);
    expect(seen, isEmpty);
    await sub.cancel();
    flow.dispose();
    await port.close();
  });

  test('RC125 start and cancel are single-flight and terminate after disposal',
      () async {
    final port = _Port()..pendingUpload = Completer<UploadFlowReceipt>();
    final flow = ResumableUploadWorkflow(port);
    final first = flow.start(resume: false);
    await flow.start(resume: false);
    expect(port.uploads, 1);
    await flow.cancel();
    await flow.cancel();
    expect(port.aborts, 1);
    port.pendingUpload!.complete(_receipt);
    await first;
    flow.dispose();
    await flow.start(resume: false);
    expect(port.uploads, 1);
    await port.close();
  });
}
