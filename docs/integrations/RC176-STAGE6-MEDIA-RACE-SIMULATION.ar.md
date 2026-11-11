# RC176 — Stage 6 Media / Permissions / Identity simulation acceptance

**11 November 2026 — SIMULATION / SOURCE ACCEPTED, NOT MOBILE E2E**

## Executed evidence

- Disposable Node 22.16.0 simulation with mock Fable server and synthetic users/assets: **4/4 new race tests PASS**, plus **16/16 RC175 tests PASS** after the response-boundary change. Combined RC174+RC175+RC176 local model tests: **27/27 PASS, 0 FAIL**.
- Read-only verification of **16/16 explicit source invariants** on current Fable Flutter GitHub files: authenticated, exact Fable media upload operations; independent Other Backend roles; local checkpoint SHA256; typed protected metadata; playback identity invalidation, cancellation and expiry; unavailable hardware/LOCAL encryption never exported.
- The new `test/rc176-stage6-media-source-contract-audit.test.mjs` preserves these invariants as a regression gate for a full Flutter checkout; the **full Node source test command was not run on a local clone** this turn. Assertions were separately checked through the connected GitHub source. No GitHub Actions.

## New race simulations

1. Media permission revoked while a mock response is pending => no bytes returned.
2. Logout while media pending => discard stale response.
3. A→B→A account switch => old A request remains invalid despite identical final username.
4. Server revokes the session while a mock request is pending => deny before returning bytes.

To make the simulation reflect the network boundary, the RC175 model now awaits the synthetic network pause **before** checking the live simulated session/ACL and returning bytes. This is a test model change only; no Dart/Flutter/Backend production code was modified.

## Limits

- The cryptographic key in RC175 is a Node software test key. Hardware-backed DPoP on Android/iOS was not executed.
- Flutter native players, real media content-range delivery, upload/DRM, backend object-store deletion and actual permission propagation were not exercised. `NONE/LOCAL/DRM` separate runtime-tier simulation is Stage 6.4.
- All 17 mobile families remain `complete:false`, `liveE2EVerified:false`. Stage7 production readiness remains **NO-GO**.

[Eight-gate tracker](./STAGE6-8-SIMULATION-GATES-2026-11-11.ar.md) · [RC175](./RC175-STAGE6-SIMULATED-DPOP-AUTH-MEDIA.ar.md).
