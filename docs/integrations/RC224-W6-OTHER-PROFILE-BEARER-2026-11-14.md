# RC224 W6 — Other Backend personal profile must belong to a user identity

2026-11-14. Based on merged Flutter RC223 main `7a4be7e18a7ce92d9b91fa55ece78a925c5ccbdb`. Backend remains RC209.

## Actual source issue fixed
`ExternalProfileFields.fromMap` formerly accepted a public `GET /users/me` operation with `auth: none`. The page claims to display the signed-in user's own profile and holds a backend-bound secure session. A public GET or provider-level API key cannot prove an individual user identity. The imported catalog's `FableOperation.enforceAuth` alone is not enough; it may be true even for anonymous operation types. RC224 now requires `GET` **and** `requiresAuth` **and** `enforceAuth`, plus `credentialHeader==null`. Other Backend's validated `auth: bearer` operation satisfies these constraints, but `auth: none` and provider-shared credentials are refused. Existing source/operation hash bindings, safe JSON selector paths, redaction restrictions, session namespace separation and widget account-switch protection remain unchanged.

A private Backend still must enforce account ownership at the server. This source gate cannot prove deployed Backend authorization or prevent a malicious authenticated server from returning someone else's profile.

## Regressions
- Migrated the original profile fixture from an unsafe anonymous operation to a valid Bearer operation; retained previous projection/immutability tests.
- Added two Flutter tests: reject both anonymous and provider-wide credential profile reads; accept properly bound Bearer profile GET. Total **five** Dart tests.
- Added **six** Node source tests checking identity gate, contract fingerprint and secret field preservation.
- The same user command `pnpm fable:all` now also includes the Dart Other Backend profile suite. No new developer command.

**Observed:** 12/12 isolated branch-source structural/semantic checks PASS. Dart/Flutter SDK, actual project, native devices, real provider Auth and deployed API ownership/E2E remain unexecuted in this model environment. Source work does not mark any of the original 82 W0 acceptance items complete. W6 Profile and other feature families OPEN, production NO_GO. No previously merged source or PR draft was discarded; no GitHub Actions required.
