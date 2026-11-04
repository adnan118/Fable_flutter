# RC113 — P3 Media: Guarded Authenticated Byte-Range Transport

**Base:** Flutter/main `8869ef7365d4355c14d471a9bba8ae3ad43ba76d` (RC112, post-merge CI 3/3).
**Server evidence:** Fable RC66 `src/platform/media/media.controller.ts`: authenticated `GET /media/:id/content`, `media.access` / `media.read`, `x-fable-media-token` header, HTTP Range and 206 Partial Content, `Cache-Control: private, no-store` for protected responses.

## Implemented
- `FableAuthGateway.requestProtectedContentRange` reuses the existing verified Fable transport for BOTH normal account `Authorization: Bearer …` and the extra short-lived `X-Fable-Media-Token`. No second manual Dio client, ambient credentials or external host.
- The shared `UnifiedApiClient.request(mediaRange: …)` allows this secret-bearing mode **only** when a signed `FableContract` operation uniquely identifies a protected `GET /media/:id/content` route, with no query/body/managed-entity/security challenge, UUID path, explicit bounded `Range` (maximum 512 KiB), and Fable transport adapter. All other operation IDs fail before dispatch.
- Fable's existing auth request pipeline retains identity-epoch checks, redirect blocking, token renewal and authorization handling. The binary request uses `ResponseType.stream` instead of JSON, `Accept-Encoding: identity` and `Cache-Control: no-store`.
- `FableProtectedMediaPlaybackRepository.readContentRange` discovers the content operation separately from RC112 playback/refresh/end. Absence or public declaration disables byte reads; projects without a media content export are never assumed to support them.
- Each byte read is pinned to the active playback view/session and current Auth epoch. Validate HTTP **206**, `Content-Range` exact requested interval (or the available EOF), `Content-Length`, declared Content-Type, `no-store`, uncompressed bytes, exact byte count and 512 KiB maximum. Reject 200 full bodies, redirects, mismatches, excessive bytes and truncation.
- Tokens remain private in memory. The caller receives only the verified bounded `Uint8List` chunk, never an authenticated URL, media token, or native player header map.
- In-flight reads are cancelled on login/logout/account switch, refresh token rotation, playback end and disposal. Stale bytes fail closed.
- No global playback URL query token (even though Backend may optionally accept one in legacy configuration). There is no new app-level token persistence.

## Simulated verification
`packages/features/fable_media/test/protected_media_range_rc113_test.dart` uses real `FableAuthGateway` + fake Dio responses and in-memory Auth events to exercise:
- content route missing or public, blocked before network;
- correct Fable bearer plus media header, `Range`, no URL query and no redirect;
- HTTP 200/302, incorrect Content-Range and length, oversized bytes and requests;
- A→B while reading a chunk; end while reading; refreshed token invalidates old view;
- wrong operation ID cannot inject media header on playback POST.
`test/rc113-protected-media-range-audit.test.mjs` enforces key source guardrails in CI.

## Incomplete / P6 pending
- RC113 is a **byte-range transport adapter**, **not** a running Android ExoPlayer or iOS AVPlayer component. Native plugin byte-source callbacks, per-platform streaming playback performance, DRM/FairPlay/Widevine and secure surfaces are separate integrations requiring proper native capabilities and device evidence.
- This does **not** certify Backend/DB/R2 streaming, actual server range behavior, Media authorization grants in deployed project, native users/devices, or end-to-end playback. CI fake-Dio and build checks are simulations.
- The checked-in `assets/contracts/openapi.json` fixture currently does **not** export playback or content operations. Enabling this feature requires selecting Media in an actual Backend project and importing the signed project contract.
- Backend enforcement on every byte request and revocation remains authoritative. An already-delivered byte buffer cannot be retroactively removed; the client never caches ranges to disk.
- Other Backend remains unsupported for this Fable-specific transport until it supplies independently verified content operations and credential/response semantics.

**No P6 `liveE2EVerified` promotion.**
