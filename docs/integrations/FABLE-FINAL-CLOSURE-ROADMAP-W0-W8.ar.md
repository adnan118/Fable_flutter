# Fable — Final Closure W0–W8 / خريطة الإغلاق النهائي

**2026-11-12 — W0 inventory created; this document does not certify feature or production readiness.**

## Project outcome

Build an actual Backend+Flutter project correctly in either of two paths: developer guided setup or agent headless command setup, using a complete versioned selection manifest and independently verified Backend contract. No selected feature or option may be silently omitted; no invented endpoints, roles, permissions, DTOs, credentials, provider contracts or deployments.

**Master work plan:** https://github.com/adnan118/Fable/issues/56  
**Flutter workstream:** https://github.com/adnan118/Fable_flutter/issues/98  
**Authoritative machine-readable W0 gap inventory:** `docs/integrations/FABLE-FINAL-CLOSURE-W0-GAP-REGISTER.json`  
**Source of feature truth:** `docs/integrations/FABLE-FLUTTER-PARITY-MASTER.json`

## Baseline from real source

- **17/17 feature families remain `complete=false` and `liveE2EVerified=false`.** Prior source/model simulation acceptance does not change those states.
- **60 feature-specific gaps** copied exactly from the prior master ledger under stable FAM-* IDs. These are open action/evidence items, not 60 independently reproduced defects.
- **10 cross-cutting open/unverified checks** cover Backend/Flutter Wizard and generated source, contract handoff, Other Backend isolation, full Backend and Flutter toolchain, real providers and human production authorization.
- **12 clean generated-project scenarios:** Fable versus Other Backend × developer versus agent × minimal/standard/complex.
- The current Flutter Wizard source labels verified imported decisions `implementation.status='requires-feature-binding-review'`. RC105 docs state arbitrary project-specific feature repositories are not fully automatically generated. Therefore merely choosing a feature is not proof of a working end-to-end user flow.
- `npm run test:closure:w0` has 12 executable Node source/inventory checks. The exact 12 authored JS test bodies were separately executed in V8 against the actual GitHub JSON files (12/12 PASS). Full `node --test` in a checked-out Flutter repository was **not** run in this conversation.

## Execution gates and their hard exit conditions

| Gate | Work | Evidence required |
| --- | --- | --- |
| W0 | Complete truthful gap inventory and normalized project acceptance manifest | Source-grounded matrix, all gaps assigned, pinned sample projects; no simulated E2E |
| W1 | Backend Guided Wizard vs Agent parity | Same normalized generated project under equivalent explicit choices; no extra hidden defaults |
| W2 | Generated Backend complete capabilities + transactional safety | Real generated source/routes/migrations/env/permissions; rollback, safe re-run and tests |
| W3 | Backend to Flutter handoff | Exact contract/OpenAPI/operation/DTO/role/tenant and project SHA/origin checks; no forged endpoints |
| W4 | Flutter Wizard Fable vs Other Backend, developer vs agent | All 12 generated-project paths with review/apply/retry, Fable-only DPoP isolation |
| W5 | Generated feature and UI integration | Real repository/typed operation/state/navigation/RTL/error/test trace or explicitly BLOCKED |
| W6 | All 17 stable feature families | Full selected subfeature support and direct functional test evidence, never flags alone |
| W7 | Adversarial/integration/toolchain acceptance | Available local tests + owner-executed Node24/Flutter SDK/devices/providers/DRM/payment/cloud results, each cited |
| W8 | Final delivery and code/evidence sign-off | Merged commits, tests, examples and user-check packets; production GO separately authorized |

## Source merge and user environment test rules

1. **Any available code fix passes available tests, receives a PR, is merged into `main`, and is recorded.** Do not accumulate drafts as untracked debt.
2. **All identified unresolved work must be logged** in the W0 register with severity, expected test, repo and responsible party. A new unknown issue found later is appended; it cannot be silently excluded from the scope.
3. **Tests needing a real environment belong to the user:** Node 24/pnpm 12 frozen install and audit; full Jest/Prisma/MySQL; Flutter analyze/test; real Android/iOS native DPoP; chosen payment providers, licensed DRM and media; Redis/S3/R2/WAF and durable outbox; KMS/offsite restoration and real pager/rollback. Provide exact commands and expected output, accept test evidence only when the user runs it.
4. **Do not weaken security to pass:** Flutter Fable DPoP is enabled by default, Other Backend must not receive Fable DPoP, DRM no downgrade, server-authoritative money settlement, tenant/role isolation and independent human production approval remain mandatory.
5. **Different completion gates:** `SOURCE_IMPLEMENTED`, `TESTED_ON_AVAILABLE_ENV`, `USER_REAL_E2E_VERIFIED`, `PRODUCTION_APPROVED`. These cannot substitute for each other.

**Next development increment:** W0.2 canonical project manifest + W0.3 executable gap classification; then W1. Do not wait for the user to test actual devices to fix source bugs, but keep device E2E open and provide them a reproducible checklist.
