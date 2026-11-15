# Fable — RC242 source checkpoint (2026-11-15)

This is a **source continuity checkpoint**, not a native E2E result or production release approval. No historical W0 gap baseline is rewritten.

## Exact merged main commits

- Backend: `adnan118/Fable` `main` at **`d05db1d8bae39387ada03b363d4db1f5268ce716`** (RC241).
- Flutter: `adnan118/Fable_flutter` `main` at **`c26c03c83a33af3c42f9a2db199793a6a03d9bfe`** (RC242, before this documentation-only merge).

## Changes merged since RC236

| RC | Repository | Merged PR | Actual source changes |
| --- | --- | --- | --- |
| RC237 | Flutter | #129 | Fable-only protected Passkey DELETE with recent-auth proof and verified optional list; extends precise Fable transport header allowlist |
| RC238 | Flutter | #130 | Per-language single-flight client-copy sync, prevent storage failure from replacing fresh network text |
| RC239 | Backend | #75 | Passkey login enrolls DPoP server-side; verified thumbprint forwarded to session issuer; runtime and generator blueprint mirror |
| RC240 | Flutter | #131 | Verified public Passkey authentication POST signs a native DPoP bootstrap proof, with server policy preflight |
| RC241 | Backend | #76 | Export existing protected GET /auth/passkeys as `passkeys.list` in blueprint manifest v1.3.1 |
| RC242 | Flutter | #132 | Auto-select `passkeys.list` only when the currently imported Fable project contract explicitly exports it |

The earlier RC228–RC236 changes remain in Flutter `main`; do not replace it with RC229 source or flatten/overwrite unrelated history.

## Scope and unfinished implementation

- Code changes above are merged; **Flutter toolchain/native/device tests not executed here** and neither installation on a real device nor real provider E2E is claimed.
- A concrete Android Credential Manager and iOS AuthenticationServices Passkey adapter is still needed; Flutter enrollment and authentication use explicit native interfaces, not a completed native implementation.
- Generated project-specific UI route/repository/state binding for every selected capability (W5) and full functional completion of the 17 feature families (W6) remain unapproved.
- Other Backend operations are explicitly mapped and never inherit Fable Passkey/DPoP paths.
- The original W0 register and its 60 feature-specific historical gaps, 10 cross-cutting checks and 12 wizard-generated scenarios remain intact and should not be silently counted as closed.
- Backend & Flutter real test environments, providers, Android/iOS, audit, independently authorized final production signoff (W7/W8) remain outstanding; release decision **NO_GO**.
- Continue implementing real, contract-backed missing code in small batches, merge to each repository's `main` immediately, preserve legacy source, and distinguish SOURCE_IMPLEMENTED from verified runtime behavior.

## Verification behavior

No GitHub Actions outcome or source-only audit is represented here as proof of production safety. The user explicitly asked to prioritize source completion and postpone device/toolchain tests. The repository-level acceptance command remains `pnpm fable:all`, but it has not been executed for this checkpoint.
