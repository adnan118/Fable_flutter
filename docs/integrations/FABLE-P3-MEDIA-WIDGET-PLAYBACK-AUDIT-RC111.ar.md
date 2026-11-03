# RC111 — P3 Media Widget lifecycle + Playback audit

**Flutter reference:** `adnan118/Fable_flutter@af0cd76456805ebf4561d3419dd057d6b10f03a5` (RC110 main).
**Backend reference:** `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932`, `Fable-Backend-RC66`, capability `media` manifest and `src/platform/media/media.controller.ts`.

## 1. UI gap closed — account/file/Backend switch

RC110 fixed repository request identity, but the `FableResumableUploadCard` widget could still retain
a previous file's progress/checkpoint after parents reused the same StatefulWidget instance.
A delayed `checkpoints.read`, `saveCheckpoint`, `onProgress`, or `onCompleted` could
update the new user's widget or clear its new checkpoint store.

RC111:
- `didUpdateWidget` treats a different `File` instance, Repository, CheckpointStore,
  account scope, kind/MIME/visibility/purpose as a new source. The old CancelToken is
  cancelled immediately, in-memory progress/completion is reset, and checkpoint restore
  restarts only for the new explicitly provided repository and store.
- A Media repository exposes `currentIdentityRevision`, `isSameIdentity`, and
  `identityEvents` from its **own selected Backend's session**. For Fable, they come
  from `FableAuthGateway.session`; for Other Backend, a verified external
  `identityEvents` stream must be provided explicitly to enable this widget.
- Identity events revoke the widget immediately, clear visible old progress and stop the
  old in-flight transfer, without automatically re-enabling uploads under the new user.
  Reopen/rebind the widget with the new account-scoped Repository and CheckpointStore.
- Every async restore, chunk progress callback, checkpoint write/clear, Cancel and
  completion checks both its UI generation and the original authenticated epoch.
  The caller's `onCompleted` is suppressed for stale or cancelled work.
- Cancel captures the *old* Repository and CheckpointStore and saves local cancel intent
  before optional server DELETE. It never uses `widget.checkpoints` after a switch.

## 2. Deterministic widget simulation, not real E2E

`packages/features/fable_media/test/media_widget_lifecycle_rc111_test.dart` exercises:
old prepare response after file+repository replacement, account change event during pending
upload, delayed checkpoint restore, cancel followed by new account widget, and an Other
Backend repository with no identity events (actions disabled). Other existing RC110 tests
continue to cover R2/local chunk/network races. Flutter widget tests use fake HTTP and
in-memory checkpoint storage; they do not prove native filesystem/DB/R2/real session behavior.

## 3. Backend playback contract review — not guessed or implemented in RC111

The Fable RC66 media capability manifest declares 16 routes. It includes:
- `POST /media/:id/playback` — authenticated and `media.access`+`media.read`.
- `POST /media/playback-sessions/:id/refresh` — authenticated and the same permissions.
- `DELETE /media/playback-sessions/:id` — authenticated and the same permissions.
- `GET /media/:id/content` — authenticated `media.read`; the controller accepts
  `x-fable-media-token`, with query playbackToken allowed only when
  `MEDIA_PROTECTION_ALLOW_QUERY_TOKEN=true`. Protected responses set
  `Cache-Control: private, no-store` and related security headers.

**Not done:** There is no implementation of the three playback calls on the Flutter client
in RC111. A manifest route is NOT evidence that a particular project contract exports
that operation. Before adding them, check the installed project's generated operation IDs,
method+path+Auth+role, request/response DTO, playback lifetime, refresh expiry,
consumption in native player, credential transport, and whether Other Backend exposes
equivalent semantics. In particular, never put a playback token into a URL by assumption.

## Remaining risks and P6

- A File object may refer to bytes modified at the same path while upload is running.
  RC110 re-hashes on resume; it does not guarantee continuous file immutability.
- A server mutation completed before client cancellation cannot be rolled back by widget
  cleanup. Backend TTL, upload session status, and orphan multipart cleanup require E2E.
- The OS storage used by `MediaUploadCheckpointStore` remains app preferences scoped by
  a caller-supplied SHA-256 backend/account key. The caller must rotate this scope on
  logout/account/backend switch. No signed URLs or media credentials may be persisted.
- This slice does not mark any of 17 families `liveE2EVerified` or `complete`.
