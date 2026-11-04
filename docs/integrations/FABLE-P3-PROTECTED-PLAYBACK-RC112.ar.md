# RC112 — P3 Media: Protected Playback Session (Fable-only)

**Flutter baseline:** `e45e11fdbb2306f5e48f92a79e96773278c3363a` (RC111 main CI 3/3).
**Backend source:** `adnan118/Fable@226cbcdc542ebe9c005d7445d84cc0ec10631932`, `Fable-Backend-RC66/src/platform/media/{media.controller.ts,media.service.ts,media-protection.service.ts,dto/media.dto.ts}` and `blueprints/capabilities/media/manifest.json`.

## What RC112 implements
- `FableAuthGateway.verifiedContract` is a **read-only** view of the already-imported and verified Fable project contract.
- `VerifiedFablePlaybackBindings.fromGateway` discovers **operation IDs from the current project's actual OpenAPI** by matching all three verified protected verb/path pairs:
  - `POST /media/:id/playback`
  - `POST /media/playback-sessions/:id/refresh`
  - `DELETE /media/playback-sessions/:id`
  and requires a unique operation for each, `requiresAuth=true`, `enforceAuth=true`, and 64-hex operation contract hash. Both `{id}` and `:id` forms are recognized. A project that does not export all three is **unsupported**, with no guessed operation IDs, fallback routes, or network dispatch.
- `FableProtectedMediaPlaybackRepository` is **FableAuthGateway-only**. Other Backend is deliberately unsupported until it has its own independently verified operation schema, response semantics and identity interface. The Fable Auth namespace is never silently applied to it.
- `open` accepts only Android/iOS and optional caller-supplied grant token, receives `enabled=true`, `type=AUTHENTICATED_STREAM`, the server playback session and strictly time-bounded `accessToken`. It validates exact stream URL `/media/:id/content` and exact `X-Fable-Media-Token` header; it rejects `STANDARD`, `MULTI_DRM`, token-in-URL, expired or inconsistent responses.
- `refresh` validates that the Backend returns **the same session and asset IDs** with a renewed short-lived token. It invalidates the previous view to prevent accidental reuse.
- `end` clears local access token *synchronously* before an authenticated DELETE, rejects mismatched results, and never replays a possibly committed mutation automatically.
- `FableSecureSession.identityRevision/identityEvents` revoke cached playback credentials on login/account replacement/logout; a delayed open/refresh cannot reattach old credentials. `dispose` clears local tokens.
- `ProtectedMediaPlaybackView` contains only non-secret metadata and prints a redacted string. The additional media access header can be obtained **only while the current view, authenticated identity and token TTL are valid**. Nothing is persisted to disk, logs, preferences or URL query parameters.

## Production limits explicitly NOT completed
- **No native media player or DRM license/manifest code.** The returned `X-Fable-Media-Token` is only the *additional* header: Backend content also requires normal authenticated session credentials (`PermissionGuard` and `media.read`) supplied by a separate verified transport. Do not make raw network requests or assume the additional header alone grants playback.
- Backend may return `enabled=false,type=STANDARD` when protection is disabled; RC112 rejects that as outside the protected-stream contract instead of silently assuming it has a protected session.
- This does not assert installation of the Media capability in the user's actual target project. The static test assets in Flutter/main intentionally **do not export playback routes**; project availability is conditional on a verified imported Backend contract.
- The Backend remains authoritative for authorization, revocation, range/no-store, refresh TTL and concurrent-session limits; client checks are defense-in-depth, not DRM.
- **No real Backend/MySQL/R2/FCM, Android/iOS device, native playback or license-server E2E**. P6 remains open. Tests use a FableAuthGateway with a fake Dio transport and in-memory Auth event stream.

## Source-backed response model
The Backend RC66 `MediaProtectionService.playback` returns `playbackSession.id/expiresAt/idleExpiresAt`, `accessToken`, `accessTokenExpiresAt`, `stream.url` and `stream.authorization`. Refresh returns `playbackSession.id/assetId/expiresAt/idleExpiresAt` with new tokens. End returns `{id,status:'REVOKED'}`. The service wraps them via `apiSuccess`, which is unwrapped from `data` when present. The server supports other options (including Multi-DRM), but RC112 exposes no unverified native handling.

## Mock test matrix
`packages/features/fable_media/test/protected_media_playback_rc112_test.dart` covers:
- missing/public/mismatched project operation contract: fail before HTTP;
- successful Android open/refresh/end with session-bound token rotation;
- A→B during delayed `open`, active-session logout, and refresh arriving after end;
- expired tokens, standard/DRM responses and injected token-in-URL rejected;
- mismatch of asset/session in refresh, end revokes access immediately.

CI: Node contract-source audit, Flutter analysis and all package tests, Android debug APK and unsigned iOS simulator build, all on the exact PR head. These are **simulation/build checks**, not live acceptance.
