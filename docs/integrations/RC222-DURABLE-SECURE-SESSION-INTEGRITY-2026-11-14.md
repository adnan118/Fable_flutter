# RC222 — fail closed on interrupted access/refresh secure storage writes

Date: 2026-11-14. Flutter main baseline RC221 `ca18789c03a601c69aad92b2eae7f53c286894f6`, Backend RC209 unchanged.

## Actual W6 Auth bug corrected

Previously, `FableSecureSession.replaceTokensIfIdentity` and `clearSessionIfIdentity` incremented the identity revision **before** writing or deleting all native secure-storage keys. If the first write succeeded and the next write failed (disk full, Keychain/Keystore exception, platform interruption), the process could expose a new access token with an old refresh token, or keep a partially cleared session. The revision might claim a new identity even though the new credentials were never fully committed.

RC222 changes production Dart code in `packages/fable_core/lib/src/fable_session.dart`:
- Adds a **nonsecret, per-project secure-storage integrity marker** `<namespace>.session.integrity`. `updating` is written before the first credential mutation and `ready` only after the access and refresh operations finish.
- Access/refresh getters now acquire the same namespace write queue, read the durable marker, and return **null** if a prior transaction was interrupted. A process-local unsafe namespace set provides immediate fail closed after a native write/delete exception.
- A failed native mutation invalidates the identity epoch and publishes an unauthenticated event; stale HTTP/refresh responses cannot reuse the old identity. A **successful** Login/Logout advances the identity epoch only after both secret keys and the ready marker have been committed.
- Existing pre-RC222 sessions with no integrity marker remain readable for backward compatibility until the first successful refresh, login or logout, which creates the marker.
- New full, verified login or successful clear can recover from the interrupted marker. Unknown/corrupt non-null markers never authorize token access.
- No token, refresh secret, response payload or storage value is logged. No Auth contract/DPoP policy or other Backend namespace is altered.

## Tests authored

`packages/fable_core/test/rc222-secure-session-integrity_test.dart`: **10 Flutter tests** use an in-memory, fault-injectable secure-storage implementation to check successful commit sequencing, held concurrent native writes, access reads waiting for the commit, failed refresh write, failed logout delete, full-session recovery, persistent interrupted marker at simulated app restart, legacy credential compatibility, namespace isolation, and failed initial integrity write.

`test/rc222-secure-session-integrity-source.test.mjs`: **8 Node source tests**, including commit order, no direct unsafe read path and single-command test preservation. Both suites are automatically covered by the **unchanged** single user command:

```sh
pnpm fable:all
```

## Verification limits

- **19/19 isolated source/functional ordering assertions executed PASS** against exact candidate GitHub source blobs, including correct ordering of marker/credential/epoch updates, serialized token reads and test wiring.
- **These are NOT full `flutter test`/Dart compiler results**. The model runtime has no Flutter SDK or full private source; the ten authored Flutter fault-injection tests still require execution on an eligible Flutter development environment. A physical Android Keychain/Keystore failure test and real provider/device E2E remain independent acceptance requirements.
- Original 82 W0 release evidence items stay open until externally verified. W6 Auth overall, other 16 families, W7/W8 and production remain **NO_GO**. The update does not remove any historical development.

This patch corrects a real session-integrity hazard at the source layer but cannot be certified as production-ready without native tests and owner review.
