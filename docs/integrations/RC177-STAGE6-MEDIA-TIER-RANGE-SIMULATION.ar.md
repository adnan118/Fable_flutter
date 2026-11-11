# RC177 — Stage 6 Gate 6.4: Media NONE / LOCAL / DRM, encrypted Range simulation

**Executed 2026-11-11 | 20/20 Node tests PASS on disposable local Node 22.16.0 | simulation acceptance, NOT production or native playback approval**

## Source and test

- `tools/rc177-stage6-media-tier-simulator.mjs`: an independent **Node-only test double**, not imported by Flutter or NestJS production code.
- `test/rc177-stage6-media-tier-simulator.test.mjs`: 20 actual executed Node tests with synthetic random file data, disposable AES keys and fake users.
- `npm run test:stage6:simulation`: includes RC174/175/176/177 simulation suites when executed in a full repository checkout; do not claim that this full-checkout command was run in this turn.
- Flutter sources reviewed: `domain/media_read_models.dart`, `data/fable_media_read_source.dart`, RC112/RC113 protected playback/Range docs. Existing Flutter code defines `none/local/drm` and requires protected media grants. Backend is authoritative.

## Verified mock scenarios

1. NONE remains protected by authentication/authorization, even with unencrypted media at rest.
2. LOCAL encrypts file chunks with real Node AES-256-GCM and synthetic server-only keys; exact full-file reconstruction by bounded 512 KiB Range reads.
3. Cross-chunk unaligned Range reconstructs correct bytes; malformed, oversized, out-of-file Ranges are denied.
4. GCM tag, nonce, ciphertext, reordered chunk and altered authenticated-context mutations fail closed before returning plaintext.
5. Lost key refuses decryption; incorrect synthetic replacement refuses decryption; only the matching synthetic key can decrypt.
6. DRM cannot silently degrade to NONE/LOCAL when a licensed packager is unavailable. **No licensed DRM, FairPlay, Widevine, KSM/CDM or playable native stream was simulated as working.**
7. Expired/revoked playback sessions, withdrawn grants, cross-user access and stale asset generations are refused.
8. In-flight mock Range is re-authorized after pause and before returning bytes.
9. Media metadata is scoped by owner and active rights, does not expose AES secret, bearer, storage key or URL.
10. Same-or-older asset generation cannot replace an existing asset and preserve stale playback claims.

## Acceptance meaning

**Stage 6 Gate 6.4 = DEVELOPMENT SIMULATION ACCEPTED.** This tests protocol invariants in independent Node code only. It is **not** a proof of the existing Dart/Flutter media implementation, the actual NestJS crypto gateway, network Range/HTTP 206 response handling, MySQL/R2/S3 backed media, DRM license server or Android/iOS player. Proprietary DRM remains **blocked by cost/approval until a licensed provider is selected**, and no automatic fallback is allowed. All 17 Flutter mobile capability families retain `complete=false`, `liveE2EVerified=false`; Stage7 PRODUCTION GO remains **NO-GO**.

[Stage6 tracker](./STAGE6-8-SIMULATION-GATES-2026-11-11.ar.md) · [RC113 Flutter Range source](./FABLE-P3-MEDIA-RANGE-RC113.ar.md).
