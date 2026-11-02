# Fable RC97 — Auth 40/40 source ownership closure (not live E2E)

## Scope and acceptance language
All forty RC66 Auth contract operation IDs are classified and reviewed at their **owning client source** level. Do NOT present this as forty production-approved routes. Actual Backend/DB/providers/browser/device E2E remains 0/40 accepted.

| Owner | Source reviewed | Classification |
| --- | ---: | --- |
| Flutter Mobile | 31 | `SOURCE_IMPLEMENTED_E2E_PENDING` |
| Web cookie client | 7 | `WEB_CLIENT_SOURCE_REVIEWED_E2E_PENDING` |
| Admin dashboard client | 2 | `ADMIN_CLIENT_SOURCE_REVIEWED_E2E_PENDING` |
| Unassigned | 0 | No unclassified Auth operation |

### Mobile (RC94 + RC95 + RC97)
- Google/Apple challenge and signed SDK credential validation in `fable_social`. The native SDK is injected by the host project; no fake Google/Apple tokens or client secrets are embedded in Flutter.
- Username check/update have explicit Backend routes, UI and mock regression tests.
- LOGIN-purpose public OTP request/verify/complete create a session only after Backend confirmation. PASSWORD_RESET proof must never create a LOGIN session.
- Social Google/Apple Link requires account-scoped recent OTP verification; Unlink uses the exact Backend route and recent-auth header and rejects missing/foreign confirmations. Account settings UI shares the same Auth gateway and secure session, and never invents links or a user's membership.
- Social 2FA starts the existing 2FA flow; the first factor cannot create a session by itself. Forced-password-change policy checked before storing session tokens.
- Native SDK credential/nonce, real OTP delivery, Apple/Google configuration, concurrent sessions, cross-device revocation and real DB/permissions require P6 acceptance.

### Web (seven operations, NOT Flutter Bearer transport)
- `auth.web.login`, `auth.web.refresh`, `auth.web.social.google`, `auth.web.social.apple`,
  `auth.web.2fa.login.request`, `auth.web.2fa.login.complete`, `auth.web.otp.login.complete`.
- Canonical code: private Backend RC66 branch `clients/fable-web-admin-auth.mjs`, mirrored for reliable CI in this repository under `interop/web-admin/fable-web-admin-auth.mjs`.
- Browser same-origin `credentials: include`, HttpOnly cookies held by Backend, readable CSRF cookie/token strictly for mutating requests. Browser does **not** read access or refresh secrets or set an Origin override.
- Google/Apple state/nonce and provider tokens come from an approved browser SDK; challenge and one-time completion are checked. 2FA and LOGIN OTP proofs cannot be reused or substituted for password reset.
- No implicit Web session is accepted before Backend cookie acknowledgement.

### Admin (two operations, NOT ordinary Flutter user flows)
- `auth.password-policy.get` requires server permissions.
- `auth.password-policy.update` requires server permissions, recent AAL2, CSRF for cookie auth and optimistic If-Match version. Client enforces DTO ranges and never disables the security floor.
- UI screens belong to each host's Admin dashboard, not Flutter Mobile; SDK and simulated HTTP contract were source-reviewed.

## Test evidence
- RC97 Flutter source tests: Username and OTP UI smoke, social account binding UI, existing RC94/95 mock Backend tests.
- RC97 Node Web/Admin HTTP simulation: `node --test test/web-admin-auth-client-rc97.test.mjs`, wired into Flutter CI because private Backend Actions cannot start properly. Backend has an equivalent `test/web-admin-auth-client.test.mjs` fixture.
- CI is a **source/mock gate**; it does not demonstrate database-backed sessions, live OAuth, SMS/email, Web cookies in a real browser, or production admin authorization.
- Fable Core 17-family map and P0–P7 priorities remain intact. Continue P2/P3; do not restart Auth design because Web/Admin are different owners.

## Risks not hidden
- Backend private Actions runner blocker and full source ZIP remain independent P0 work.
- Host Web/Admin UI composition and provider credentials are project-specific integration items and cannot be invented in a framework repository.
- Fable Backend RC66 live runtime source was not modified. Un-synchronized user-local files remain outside these GitHub source SHAs.
