# Fable source checkpoint — 2026-11-15, RC249 Backend / RC248 Flutter

**Actual merged source pins before this documentation-only merge**

- Backend `adnan118/Fable@bbdc4748ae220970e5f5ba205fec572c14f122a4`
- Flutter `adnan118/Fable_flutter@8d06ab7f88dff521eed8f9ef261e8dab086a7c47`
- Both repositories had zero open PRs immediately after these merges.
- This document extends, and does not replace, `RC242-SOURCE-CHECKPOINT-2026-11-15.md`.

## This execution batch (all merged into main, source implementation only)

| Version | Repo | PR | Merged source change |
| --- | --- | --- | --- |
| RC243 | Backend | #77 | Passkey DTO input bounds, v4 challenge UUID, fail-closed WebAuthn counter precision; runtime + generator blueprint |
| RC244 | Backend | #78 | Idempotent handler observable cancellation/empty/error/multicast handling; quarantine uncertain side effects, stop heartbeat; adds 5 Jest tests (authored, not run); runtime + blueprint |
| RC245 | Backend | #79 | Scheduled-task retry ceiling survives worker restarts, orphaned/null leases become recoverable, exhausted READY transitions to FAILED; runtime + blueprint |
| RC246 | Backend | #80 | Exhausted READY domain-outbox entries move to DEAD instead of being invisible; audited administrative recovery retained; runtime + blueprint |
| RC247 | Flutter | #134 | Passkey list/remove parse the actual Backend `{success:true,data:...}` response envelope; no misleading raw DTO assumption |
| RC248 | Flutter | #135 | Actual optional Fable Passkey list/remove screen with Arabic/English copy, session-change fencing and independent recent-auth proof callback; host still wires the screen and native Passkey plugin |
| RC249 | Backend | #81 | Admin-only queue-health counts for FAILED/DEAD/UNCERTAIN work, optional Prisma model-safe, degraded != zero, cached 30s; runtime + blueprint |

## Invariants and acceptance still open

- Prior Backend/Flutter commits and all generator source remain intact in `main`, no forced reset.
- **Source changes are merged, but no actual Node24/pnpm, Prisma/MySQL, Flutter SDK, Android/iOS, provider, cloud or real-device tests were run in this batch.** Authored Jest source tests are not counted as passed.
- **W5**: Wizard-generated project must bind actual project-specific repository, DTO/state/navigation and safe DI for all selected operations. RC248 exports a reusable page but does not automatically wire arbitrary generated projects.
- **W6**: 17 feature families are not all complete or real E2E verified. Full 60 legacy gap rows and cross-cutting checks in W0 remain open unless separately evidenced. Native Android Credential Manager/iOS AuthenticationServices Passkey implementations and native-device verification remain missing.
- **W7/W8**: A real project with provider credentials, full tests, database recovery, load and security assessments, deployment/audit and human production approval is still needed. **Production: NO_GO**.
- Next source priority: complete verified Wizard/W5 feature bindings and native interfaces without guessed routes; then evidence-based backend resilience/tenant/load acceptance. Keep backend reliability improvements, do not erase progress, merge each subsequent batch immediately.

No passing toolchain/CI result, production certification or finished feature family is implied by version numbering.
