# Fable RC264 — merged source checkpoint

**Recorded 2026-11-15. Source continuity only: this is NOT an end-to-end, device or production approval.**

## Exact `main` source commits before this documentation merge

- Backend `adnan118/Fable`: `6020884dc47ebbc2ec335142538e44bf38582251` (RC264).
- Flutter `adnan118/Fable_flutter`: `025bf0f85c903bd771a534b77362b777da163c2b` (RC263).
- Both repositories have **zero open PRs** after the feature/security merges.

## This batch

| Code version | Repository / merged PR | Actual implementation |
| --- | --- | --- |
| RC260 | Flutter #147 | Accept both :id and {id} known signed Passkey route templates, retain enforced auth and selected capability gates; source tests added |
| RC261 | Flutter #148 | Reject stale 2FA, sensitive OTP, contact, and Passkey UI completions after account or auth gateway change |
| RC262 | Flutter #149 | Project-mode-verified CLI exports Android Digital Asset Links and Apple AASA/entitlements review artifacts from real project RP and signing identities only |
| RC263 | Flutter #150 | Derive Android native `android:apk-key-hash:<base64url sha256 cert>` and review-only Backend `AUTH_PASSKEY_ORIGINS`; Apple uses `https://RP` |
| RC264 | Backend #82 | Fail startup if enabled Passkeys RP/origin config is invalid, accept only expected native Android or matching trusted HTTPS origins, block false recovery evidence from disabled Passkeys; runtime and generator blueprint identical |

## Preserved contracts and unresolved gates

- Full historical Backend/Flutter work (including RC228–RC259) remains merged in default branches. No branch reset, no overwritten legacy source, no open pending PRs.
- The original W0 gap baseline is **not** marked closed. The 17 feature families, W5 generated operation→repository→state→UI→navigation wiring, Other Backend parity, real project matrix, and W6 live E2E remain unresolved until actual evidence.
- RC254/RC255 Android/iOS native Passkeys adapters are **source implemented**, not yet compiled/tested on real signed devices.
- Generated Passkey asset-link files require independent real signing identities, project-specific config and publication at the RP domain; the new CLI only exports review artifacts, never deploys or signs.
- Backend `AUTH_PASSKEY_RP_ID`, `AUTH_PASSKEY_ORIGINS`, `AUTH_PASSKEY_ENABLED` and actual Android certificate and Apple Associated Domains must be verified in each deployed project.
- User asked to prioritize source completion, so no full Flutter SDK/Gradle/Xcode, Prisma/MySQL, Render/provider or production tests were executed in this session. New Jest/Dart/Node test *source* is not a passing test result.
- W7/W8 operational, security, load, disaster recovery and final production sign-off still require real evidence. **PRODUCTION NO_GO**.

Continue from these exact main SHAs; complete W5 Wizard operation binding and remaining feature families without guessing endpoints, merging each source fix immediately. Once source completeness is evidenced, run real tests and security/performance audit. Do not treat RC numbering as a verified completeness percentage.
