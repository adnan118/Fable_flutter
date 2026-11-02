# Fable — خريطة الإنجاز الكاملة / Full Delivery Roadmap (RC92)

**تاريخ التحقق:** 2026-11-02  
**Flutter baseline:** \`adnan118/Fable_flutter\` main at \`cdbe9e38508426f639e85fc4061cd37c9bda156b\` (RC91, three green main checks).  
**RC92:** branch \`rc92-auth-stepup-and-session-revocation-parity\`, not part of main until PR CI passes.  
**Backend reference:** private \`adnan118/Fable\` main at \`226cbcdc542ebe9c005d7445d84cc0ec10631932\`, source \`Fable-Backend-RC66/\`. Do not publish Backend source.  
**Scope:** 17 Flutter feature families; 40 audited Backend Auth operations; 50 Backend capability blueprints (not identical to 17 mobile families); 23 shared cross-cutting decisions.

## Readiness vocabulary (mandatory)

- **Source implemented:** Gateway/Repository/UI exists and source tests run. Not a deployed Backend acceptance.
- **Partial:** some role/operations/wiring supported, not full project contract.
- **Client source:** local-only capability with platform or integration validation still needed.
- **Live E2E accepted:** only after real generated Backend/API/database/provider, native Android/iOS, permissions/failures/identity switch verified with evidence. **Currently 0 / 17 families**.
- **CI:** Flutter analyzer/Node-Dart tests/Android debug APK/iOS simulator; no signed IPA and no actual SMS/FCM/payments.

## Current status in one line

**Backend framework:** 50 blueprint manifests source available, private main pinned; private Actions still fails before steps; private full-source ZIP **not available**.
**Flutter Core:** contract-aware adapter, strict Backend isolation, session identity, security gates, Wizard, offline SQLite/Drift + foreground sync and best-effort WorkManager/BGTaskScheduler source implemented.
**Flutter RC91:** Auth **12/40** source-reviewed, **28/40** not decided; 0 live E2E.  
**RC92 (pending green CI/merge):** 5 more sensitive OTP/revocation operations; target Auth **17/40** source-reviewed, **23/40** not decided; 0 live E2E.
**Other Backend:** independently imported Catalog/Bindings, no guarantee of universal automatic feature mapping.  
**Wizard:** can select Frontend-owned features, opt in Offline, import verified Backend contracts and print per-feature Backend integration deficits via \`pnpm wizard:check\` and \`pnpm wizard:check:strict\`. A warning report is not automatic code integration.

## 17 feature families — complete matrix

| # | Flutter family | Existing source / UI level | Fable Backend basis | Other Backend | Remaining before acceptance |
|---|---|---|---|---|---|
| 1 | \`auth\` | Gateway, login, 2FA login, sessions and password change/reset UI, source tests | Auth/assurance/account lifecycle, 40 audited endpoints; RC92 target 17/40 reviewed | Partial custom auth, independent MFA contract still missing | Remaining 23 per-operation decisions, live OTP and reset/step-up/session revocation on real devices, all policy/role/error cases |
| 2 | \`profile\` | Account UI, managed account Repository and scoped entity support | Users/Managed Accounts (18 operations) | Partial mapping | Subaccounts roles OWNER/MANAGER/VIEWER, membership revocation/permission changes and live authorization |
| 3 | \`notifications\` | Inbox UI/Repository, push registration layer | Notifications, push, templates | Not proven | FCM/APNs token lifecycle, foreground/background, opt-in, per-user events, dedupe, actual delivery |
| 4 | \`media\` | Read/upload repositories, resumable upload UI | Media (16 operations) | Not proven | R2/provider integration, MIME/quota/security, resumable uploads, playback refresh/end, signed media URLs, devices |
| 5 | \`localization\` | Languages UI, client copy, locale policy | Languages | Not proven | All UI/dynamic content, RTL, generated ARB/AI/API translation policy, invalidation/caching and offline locales |
| 6 | \`support\` | Repository and UI widgets, not full ticket flow | **No support capability manifest** confirmed | Not proven | Independent verified support ticket API or keep disabled; roles, attachments and full ticket lifecycle |
| 7 | \`social\` | Auth repositories/widgets | Auth social/challenge/link/unlink | Not proven | Google/Apple native SDK, nonce/state, provider credentials, linking, collisions, MFA, provider disable |
| 8 | \`biometrics\` | Repository/widgets | Passkeys (6 operations) | Not proven | Native WebAuthn/rpId/origins/attestation integration; never equate local biometric unlock with server identity |
| 9 | \`realtime\` | Public SSE coordinator and repository | Realtime/Shared Signals/Domain Events | Not proven | Authenticated WebSocket/RTC/LiveKit scopes, subscription/replay/reconnect, logout/entity invalidation |
| 10 | \`deeplinks\` | Native link policy/dispatcher source | Client-owned; app associations depend on deployed domain | Client-only unless server sends protected destinations | iOS/Android association files, permission safe routes, notification deep-link deferral and E2E |
| 11 | \`messaging\` | Repository/widgets | Mail/Phone messaging provider; **not proof of customer chat API** | Not proven | Verified send/list/read conversation API, delivery ack and role/recipient/anti-abuse policy; no client provider webhooks |
| 12 | \`location\` | Location repository/widgets | Location Platform/Geo jurisdiction (15 operations) | Not proven | Permission, privacy, provider maps, geocoding/nearby/matrix/routes/geofence contracts and native maps |
| 13 | \`payments\` | Limited repository/widgets, safe online-only posture | Financial Platform/Commercial Access (46 operations) | Not proven | Checkout/capture/refund and idempotency/quote freshness, verified server webhook, currency + multi-role E2E |
| 14 | \`offline\` | RC89 SQLite/Drift, cache/outbox/retry/identity scope and scheduler; Wizard opt-in | Client-owned **plus per-operation server contracts** | Client-only base, per-operation server grants missing | Actual per-feature GET cache and write grants, encrypted storage classification, conflict reconciliation, background device tests |
| 15 | \`analytics\` | Repository only | Observability/System Monitoring is **not** a mobile analytics API | Not proven | Event schema/privacy/consent, roles, server aggregation, proof of dashboard or business API |
| 16 | \`content\` | Published content UI/repository/index and consent behavior | Content Pages (19 operations, 17 structured block types) | Not proven | All block renderers, policy revisions and consent, admin editor only for verified admin role; live source+DB E2E |
| 17 | \`access_control\` | Permission bootstrap/repository/authorized action UI | Access Control/Feature Flags (6 operations) | Partial mapping | Permissions + roles per project and entity, revocation on 403, live role-switch and cache invalidation |

**All 17 remain \`complete=false\`, \`liveE2EVerified=false\` in the master ledger.** Feature package installation, mocked unit tests or a compiled APK never changes that.

## 40 Auth operations — full work inventory

**Already source-reviewed before RC92 (12):**
\`auth.session-policy\`, \`auth.login\`, \`auth.refresh\`, \`auth.logout\`,
\`auth.sessions\`, \`auth.session.timezone\`, \`auth.change-password\`,
\`auth.2fa.login.request\`, \`auth.2fa.login.complete\`,
\`auth.otp.public.request\`, \`auth.otp.public.verify\`, \`auth.password.reset\`.

**RC92 target +5 (code/test/gates, pending CI):**
\`auth.otp.request\`, \`auth.otp.verify\`, \`auth.sessions.revoke-one\`,
\`auth.sessions.revoke-selected\`, \`auth.logout-all\`.

**Remaining after RC92 (23):**

- Public/social: \`auth.social.challenge\`, \`auth.social.google\`, \`auth.social.apple\`, \`auth.otp.login.complete\`.
- Contact/username/security: \`auth.username.availability\`, \`auth.username.update\`, \`auth.2fa.status\`, \`auth.2fa.enable\`, \`auth.2fa.disable\`, \`auth.contact.email.change\`, \`auth.contact.phone.change\`.
- Social account management: \`auth.social.google.link\`, \`auth.social.apple.link\`, \`auth.social.unlink\`.
- Admin-only password policy (role-gated; not consumer UI by default): \`auth.password-policy.get\`, \`auth.password-policy.update\`.
- Web-only transport (separate HttpOnly cookie/Origin/CSRF rules; **do not** port into Flutter as bearer): \`auth.web.login\`, \`auth.web.refresh\`, \`auth.web.social.google\`, \`auth.web.social.apple\`, \`auth.web.2fa.login.request\`, \`auth.web.2fa.login.complete\`, \`auth.web.otp.login.complete\`.

**Important:** \`VerifyOtpDto\` for public/authenticated OTP is 6–10 chars; 2FA login DTO is separately 4–10 chars. Fable source reviews do not authorize a universal Other Backend contract.

## Cross-cutting Core / Wizard / Delivery workstreams

| Workstream | Done in reusable source | Still missing |
|---|---|---|
| Backend isolation + BFF-like mobile transport | Verified operation catalog, host/origin pin, route-method authorization, immutable auth identity, guarded conditional operations | Actual generated Backend deployment and live contract hash, no cross-Backend credential leakage tests on devices |
| Flutter architecture / Wizard | 17 packages, Frontend-owned choices and per-project approvals; source contract import, dry run / tests, localization/push/media feature scaffolding discussions | Complete per-feature Postman collection generator, DTO/BLoC/UI scaffolding with success/failure paths and Wizard UX parity for all 17 |
| Other Backend | Separate imported OpenAPI/custom catalog and explicit semantic bindings, RC90 actionable gap warnings | Verified per-feature adaptation including MFA/OTP, role-specific screens/permissions, generated working integration and live E2E |
| Offline/sync | RC89 SQLite/Drift, best-effort scheduler, client identity, retries/ACK/conflicts, foreground resume, policy in Wizard | Host workers' secure isolate bootstrap, per-Backend idempotency/version contracts, native iOS/Android scheduling tests, classified storage security |
| Localization | AR/EN and language preference mechanisms, dynamic copy source | Every feature localized, translation cache invalidation, translated notifications, RTL layouts and offline proof |
| Notifications & push | Inbox and FCM/APNs device registration source | Real provider credentials, routing and token revoke per user/device, native permission, foreground/background E2E |
| Media | Source upload/read and resumable UI | Cloudflare R2 end-to-end, large files, private playback/session refresh/end and quota |
| Roles / account subentities | Local scopes and access-control repositories | Server-authoritative managed-account and role/profile-scoped per-operation UI and immediate revocation |
| Testing and CI | Flutter/Node gates + APK debug and iOS simulator green on RC91 main | Staging generated Backend+DB+worker+provider, iOS real device/Android real device E2E, certificate signing and release smoke tests |
| Paired source ZIP and private Backend | Source pairing SHA and audited 50 manifests, Backend PR #14 open | Private Actions runner pre-step failure, private full-source ZIP generation/verification, reconcile latest pinned SHA in packager and verify hashes |

## Required execution order (no repetitive product decisions)

**P0 — Provenance and release integrity:** keep Flutter/main and private Backend PR paired exactly; fix private Actions, generate and audit one complete private ZIP. No private source in public GitHub.

**P1 — Authentication/source parity:** RC92 secure OTP & session revocations; then remaining 23 Auth decisions by domain (username/contact, 2FA status/enroll/remove, social/passkeys and OTP login, admin vs web-only classification), each with DTO+UI+errors+auth scheme and tests. Do not expand past authenticated roles without provider/identity contracts.

**P2 — Identity, roles and account context:** permissions/access_control, managed accounts and child accounts, profile and role-aware UI. Require exact Backend/Other grants and account-switch isolation.

**P3 — Common mobile platform contracts:** notifications and FCM/APNs; localization across features; Offline source and per-operation sync grants; secure media storage/R2; deeplink safety. Strictly never schedule payments as unverified background writes.

**P4 — Business capabilities:** content, social, biometrics/passkeys, realtime, location, messaging/support, payments, analytics. For missing Backend capabilities, emit terminal deficits instead of scaffolding fabricated endpoints.

**P5 — Other Backend and Wizard feature automation:** import exact external operation catalog/Postman, generate typed models, data source, BLoC and role-specific screen only after approved mappings; diagnose client-only/partial/full and require independently verified tests. No Fable route fallbacks.

**P6 — Real generated-project acceptance:** staging Backend+DB+real providers and native devices; run positive and negative API/permission/identity/offline/conflict tests for all selected feature operations; track live evidence per operation, then promote family E2E status only when all mandatory gates pass.

**P7 — Packaging and production:** security scan, private all-source archive, Android signing, Apple profiles/TestFlight, environment secrets/FCM/APNs/R2, release/cold-start/restore regression and rollback instructions.

**Immediate next after RC92:** review the remaining 23 Auth operations, start with \`auth.2fa.status/enable/disable\`, then \`auth.contact.email/phone.change\`, while preserving Web and Admin as separate contracts. Parallel track: private Actions/ZIP unblock and real staging E2E.

## No false completion rule

Do not mark any family green solely on source, CI, screen, mock API, Storybook, simulator compile, or Wizard config. An external server requires its own signed route/DTO/error/permission contract. Live device tests and server-side authority (especially sessions/payments/bookings) are independent gates.
