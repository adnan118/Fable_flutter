# Fable RC126 — Typed Media GET / Validated contract operations

2026-11-08. Flutter base RC125 merge: 6d74f7fd4fec22c70e131c7a878a5b5f5004df13.
Private Backend main source reviewed at 706aedd0bbda15149f9141ff767a901b06ffca5d; its private source is NOT copied to this public repo.

## Verified discrepancy (not guessed)
Previous Flutter media_read_repository.dart returned Future<Map<String,dynamic>> and hardcoded media.clientContract and media.metadata.
Actual Backend RC66 capability manifest and controller define media.client-contract => GET /media/client-contract requiring media.access; media.get => GET /media/:id requiring media.read.
The exact imported and enforceAuth-protected OperationCatalog must confirm both method and path before any remote call. A missing generated contract means the operation cannot run.

## Implemented
- domain/media_read_models.dart: strictly typed, immutable runtime and media asset projections. No raw response map, storage keys, grant secrets, download URL, or raw signed R2 URL enters the Domain.
- application/read_media_metadata_use_case.dart: independent MediaMetadataReadPort and UUIDv4 asset ID validation.
- data/fable_media_read_source.dart: exact Fable operation ID/path/auth checks, FableAuthGateway identity or explicit test identity revision, stale GET response rejection, validated Backend RC66 schemaVersion=12 and OPTIMIZED_PRIMARY runtime contract fields, strict media asset projection plus variants and access modes.
- media_read_repository.dart: legacy positional constructor remains available, but without an imported catalog it FAILS CLOSED and cannot emit any guessed network request. Future return types have been upgraded from dynamic maps to the typed values.
- Independent Other Backend implementations must supply their own MediaMetadataReadPort and independently verified schema/transport; no Fable operation IDs may be silently reused.

## Security and compatibility
GET media metadata may include a temporary signed URL and playbackEndpoint in the raw response, but the typed model intentionally contains ONLY the access mode, never URL or credentials. The existing playback authorization/byte-range implementation remains the only approved protected playback path.
Source compatibility is retained for constructor calls; consumers that relied on receiving a raw Map need to migrate to DTO field access. The previously guessed no-catalog reads now return a clear error rather than attempting potentially incorrect routes.
Schema mismatch, invalid enum, incorrect asset ID, malformed variants, disabled authentication or identity switch all fail closed. Simulated adapter and feature tests are not proof of deployed Backend, R2, device DRM or production acceptance.

## Acceptance
RC126 source/architecture/audit gate; Dart mocks covering schema, signed URL exclusion, identity switching, missing/wrong operation IDs and Other Backend isolation; existing RC125 and RC122–RC124 regressions; Flutter analyze/app/all-package tests, Android APK, Xcode27 UIScene iPhone+iPad, Android Media3 and iOS AVPlayer native decoder tests. Exact-head green before merge, independent main CI after merge. P6 and 17-family live E2E remain open.
