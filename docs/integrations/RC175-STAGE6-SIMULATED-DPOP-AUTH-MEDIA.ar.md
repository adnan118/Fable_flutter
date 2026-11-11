# RC175 — DPoP / Auth / Media integration model (Stage 6)

**11 November 2026 — SIMULATED DEVELOPMENT ACCEPTANCE ONLY**

## What was actually executed

- Local Node.js 22.16.0 on a disposable filesystem, no Flutter SDK, Android SDK, Xcode, production API, actual mobile keys, real user accounts, secrets, paid services or GitHub Actions.
- `node --test test/rc175-stage6-dpop-auth-simulator.test.mjs` model test suite: **16/16 PASS, 0 FAIL** (initial URL canonicalization bug found during development and corrected before acceptance).
- Combined with RC174 pure Node suite: **23/23 PASS, 0 FAIL** locally; they exercise independently authored simulation logic, **not the actual Flutter SDK runtime**.
- Separately checked eight explicit DPoP/native/transport assertions in existing current GitHub Flutter source; **8/8 source checks true**, without executing Kotlin, Swift or Dart.
- Exact model source lives at `tools/rc175-stage6-dpop-auth-simulator.mjs`; test file at `test/rc175-stage6-dpop-auth-simulator.test.mjs`. The files have to be rerun on the merged repository to obtain full-repository execution evidence.

## 16 cases

1. Real Node P-256 ES256 (P1363) signing and verification of a simulated resource proof.
2. A copied valid access token/installation label cannot replace the sender's P-256 private key.
3. Replayed DPoP proof `jti` is refused.
4. `htm`, `htu` and `ath` mismatches are refused.
5. Old proof `iat` is refused.
6. Malformed, forged, or unsigned proofs are refused.
7. Simulated Flutter refresh is single-flight and rotates credentials once.
8. Reuse of an already-rotated refresh token revokes the affected simulation session.
9. Logout invalidates the server-simulation session, not only the UI state.
10. Revocation of Media permissions blocks further access.
11. User B cannot read User A private asset even with the same role grants.
12. In-flight Media bytes from A are discarded after A→B switch.
13. Public JWK header contains no private EC scalar.
14. Non-HTTPS and query-bearing proof URLs are rejected.
15. Prior user A session is revoked when the same simulated client logs into B.
16. In-flight refresh from A cannot resurrect A after switching to B.

## Exact scope boundary

This module is **a mock test double**, not imported into the Flutter app and not a replacement for the Backend's NestJS DPoP verifier. Its P-256 private keys are generated in Node process memory solely for the test. A green result is evidence only for the proposed protocol invariants in the model, **not** proof that AndroidKeyStore / Secure Enclave, Flutter `MethodChannel`, server-issued DPoP nonces, token transport, MySQL-backed session revocation, platform Media players, real authorization or real API/DTO mappings work. These remain distinct acceptance categories.

RC174's source preflight and verified real-project contract requirement remain unchanged. We have **not** filled `backendContractHash:null` with fictitious data or altered `liveE2EVerified` flags. Stage 7 production release is **NO-GO**.
