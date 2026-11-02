# RC95 — Mobile Auth source closure and P2 handoff

## Verified baseline
- Flutter/main RC94 merge SHA: `51049f5a9550ffd1e60b4c203b23848f06a56b5f`.
- Backend private RC66 main SHA: `226cbcdc542ebe9c005d7445d84cc0ec10631932`. Backend runtime unchanged.
- Ledger before RC95: 22/40 source-reviewed; 18 unresolved. 0/17 feature families accepted via live E2E.

## Deliberate scope separation
Of the 18 unresolved Auth operation IDs, **9 are mobile-relevant**:
`auth.social.challenge`, `auth.social.google`, `auth.social.apple`,
`auth.username.availability`, `auth.username.update`,
`auth.otp.login.complete`, `auth.social.google.link`,
`auth.social.apple.link`, `auth.social.unlink`.

The **other 9 are not Flutter Mobile bearer operations**:
- Web-only Cookie/CSRF transport: `auth.web.login`, `auth.web.refresh`,
`auth.web.social.google`, `auth.web.social.apple`,
`auth.web.2fa.login.request`, `auth.web.2fa.login.complete`,
`auth.web.otp.login.complete`.
- Admin-only password policy: `auth.password-policy.get`,
`auth.password-policy.update`.

These nine remain tracked for their owning clients; do not implement Web/Admin endpoints in Flutter just to make a 40/40 counter.

## Source implementation
- RC94: Username availability/update, source-gated social challenge/sign-in/link/unlink, forced recent-auth proof, safe :param route substitution, mock tests.
- RC95: Public LOGIN OTP is purpose-specific and cannot reuse reset/contact/2FA proofs; typed one-shot challenge, verified proof, Backend session acknowledgement, mandatory-password-change handling, OTP sign-in UI.
- Social login: source-validated provider-specific response, two-factor methods and expiration, mandatory password-change and session expiry before saving bearer tokens. Social 2FA can be handed off to existing Fable 2FA request/complete flow rather than saving a session after the first factor.
- Fable/Other Backend keep distinct contracts and credential strategies.
- CI is the source/test gate; mock tests prove scenario handling but not delivery, production identity SDK, database, Apple/Google, real-device, or end-to-end safety.

## Transition to P2
When Flutter analyzer/tests and Android/iOS simulator builds pass, proceed directly to **P2 Profile & Accounts / Managed Accounts / Roles / Access Control**, without reopening Web/Admin Auth.
Keep provider SDK integration, live OTP, 2FA and multi-device acceptance in a separate E2E evidence lane (P6).
A production-ready Auth label remains **forbidden** until real E2E is accepted.
The user's unsynchronized local code is not represented by these source SHA values.
