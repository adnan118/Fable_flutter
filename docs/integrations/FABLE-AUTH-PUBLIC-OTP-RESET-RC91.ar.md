# RC91 — Public OTP + Password Reset: source-verified Flutter parity

**As of:** 2026-11-02  
**Source Backend:** `adnan118/Fable` private, audited main `226cbcdc542ebe9c005d7445d84cc0ec10631932` — do not copy private Backend code to public Flutter.  
**Status:** 3 additional Auth operations source-implemented with Flutter gateway/UI/tests, **12/40** source-reviewed; **28/40** still undecided; **0/17** live E2E.  
**Other Backend:** requires a separate catalog/auth flow; these Fable routes MUST NOT be reused.

## Backend controller / DTO parity

| Ledger operation ID | Backend Fable route | Auth | Fields | Behavior and boundaries |
|---|---|---|---|---|
| `auth.otp.public.request` | `POST /auth/otp/public/request` | Public | `purpose=PASSWORD_RESET`, `identifier` max 191, optional `preferredChannel=EMAIL\|PHONE` | If accepted: `{challengeId,accepted:true,deliveryStatus:'QUEUED',expiresAt}`. QUEUED is not provider delivery. Rejects non-accepted via Backend error; does not claim success for nonexistent account |
| `auth.otp.public.verify` | `POST /auth/otp/public/verify` | Public | `challengeId` UUIDv4, `code` string 6–10 chars (server-issued numeric) | `{verified:true,challengeId,purpose:'PASSWORD_RESET'}`, verified purpose and ID must match. No session issued |
| `auth.password.reset` | `POST /auth/password/reset` | Public | `challengeId` verified purpose-bound reset proof, `newPassword` 1–1024 characters (server enforces effective policy/history) | `{changed:true,sessionsRevoked:int>=0,twoFactorPreserved:bool}`. Backend consumes proof and revokes all sessions atomically; no automatic login |

**Careful distinction:** authenticated OTP `/auth/otp/verify` uses `VerifyOtpDto` 6–10 characters; this revision corrects `verifySensitiveActionOtp` Flutter validation to **6–10 numeric digits**. Separately, `/auth/2fa/login/complete` uses `TwoFactorLoginCompleteDto`, which explicitly allows **4–10 digits**; its Flutter rule is unchanged.

### Backend behavior to preserve

- Request public OTP only for eligible existing accounts; do not expose whether an identifier exists through Flutter error detail. The backend currently responds with generic non-acceptance for failures, not success. A `QUEUED` response is durable outbox acceptance, never confirmed email/SMS delivery.
- Honor resend cooldown, rate limits, OTP expiration/attempt limits and server error codes. Do not disable rate limiting in Wizard.
- Verification is purpose-bound; `LOGIN`, `ACCOUNT_RECOVERY` and `SENSITIVE_ACTION` proofs are not password-reset proofs.
- On successful reset, Backend updates password hash/history, revokes active sessions, and preserves two-factor configuration. Flutter must re-authenticate, never create a session from password-reset confirmation.
- A Backend response without exact verified `changed/sessionsRevoked/twoFactorPreserved` fields is not proof of success. Do not save new passwords in preferences/Drift or log request bodies.
- An uncertain network timeout is not proof of failure or success; do not send unbounded repeats or show success.

## Flutter implementation

- `packages/fable_core/lib/src/fable_auth_gateway.dart`: exact three public routes `canResetPasswordWithPublicOtp`; typed challenge, purpose-verified proof and final result; idempotent client-side rejection of already confirmed proof; identity-revision checks.
- `packages/features/fable_auth/lib/src/password_reset_page.dart`: controlled request → code verification → new password → confirmed reset, with careful status text. No local session minted or OTP/password persisted.
- `packages/features/fable_auth/lib/src/login_page.dart`: optional `Forgot password? Verify by OTP` entry only when all three exact operations are published by the Fable project contract. If missing, no fabricated reset API is exposed.
- `packages/features/fable_auth/lib/fable_auth.dart`: exports the reset UI.
- Regression tests: `packages/fable_core/test/auth_rc91_public_otp_password_reset_test.dart`, `packages/features/fable_auth/test/password_reset_page_test.dart`; compiled Flutter/Dart analyzer + Android/iOS builds by CI.

## What remains before live approval

1. Deploy/generate a real Backend Fable project with `AUTH_OTP_ENABLED=true` and correctly configured verified channels/delivery providers, using a private staging environment and test accounts.
2. Import the exact signed and pinned Backend project contract and verify the three operation IDs/methods/paths/public auth semantics, plus privacy policy/response envelopes. The CI demo contract is intentionally incomplete.
3. Live Android + iOS reset requests including queued vs actual provider delivery, 429 cooldown, invalid code, one-use verification, expiry, provider outage and no account enumeration claim.
4. Real password history/policy failures, concurrent password-change race, two-device active session revocation, mandatory relogin, preserved 2FA, and ambiguous network timeout reconciliation.
5. For Other Backend, import its own OpenAPI/custom catalog and explicitly map equivalent operations/error semantics. Never take Fable-specific response fields as a universal contract.

**Acceptance rules:** These 3 operations are `SOURCE_IMPLEMENTED_E2E_PENDING`. No claims that Backend private CI is fixed, any genuine OTP email/SMS was sent, any password changed on a real account, or any Android/iOS live E2E passed. The private full-source ZIP remains pending.
