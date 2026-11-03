# RC104 — P2 owner lifecycle OTP bound to managed context

## Source baseline
- Flutter/main after RC103: `228e63a886870460ae95c5e9eadbf5511a437a47`.
- RC94–RC103 remain preserved. The Auth 40-operation owner ledger is unchanged.
- Fable Backend still verifies the requesting user's OWNER membership, fresh OTP purpose/challenge and each lifecycle route; neither a Flutter snapshot nor local OTP confers permission.
- Live provider, Backend database and physical-device E2E acceptance remains pending P6.

## Source-level race

RC103 protects selected-entity activation and invitation dialogs, but an OWNER lifecycle OTP could have been requested when entity A was visible and then remain in the UI after a same-login switch to B, especially when no entity was selected locally. Further, a one-time OTP might be verified asynchronously after a context switch, then the repository could submit the sensitive lifecycle POST without rechecking the current UI context.

## Hardening

1. The owner action captures the exact managed store, selection revision and Auth identity **before** the action confirmation. A changed context aborts before the OTP challenge request or on late response.
2. The parent page binds each pending lifecycle proof to the original store and selection revision; any A→B→A change invalidates it and clears the OTP input.
3. A foreground membership refresh discards a pending proof if the Backend no longer lists the same user as OWNER of the entity. Failed membership reads fail closed.
4. The verify+apply repository method has an optional source-owned context callback. It checks the callback **before OTP verify and after Backend proof verification, but before the sensitive lifecycle POST**. If switching occurred, the proof may have been consumed but no lifecycle mutation is transmitted. Callers must request a fresh OTP after a context change.
5. No OTP or sensitive action is replayed on uncertain Backend completion.
6. The Wizard's cross-feature audit now checks both UI pending-OTP binding and repository post-verification mutation guard. Other Backend remains independent.

## Simulated source regressions

`packages/features/fable_profile/test/managed_lifecycle_context_rc104_test.dart` covers:

- Switching to B while the OTP verification response is held, then releasing the response: the lifecycle POST **must not occur**.
- Unchanged owner context with valid purpose-scoped proof: one lifecycle POST only.
- Switching context in the parent screen clears the pending owner OTP before it can be verified.
- Foreground OWNER→VIEWER demotion clears the OTP prompt and sends no lifecycle POST.

The exact sensitive operation IDs/paths remain sourced from the imported Fable contract; no guessed Admin or Other Backend endpoints are generated.

## Remaining

The SDK/framework cannot certify live DB revocation, OTP delivery or in-flight server-side writes using mock tests. P6 must exercise real devices, PostgreSQL/MySQL as configured, and concurrent owner/member sessions. Future Wizard-selected business feature repositories should use `executeUsingStore` explicitly for managed-entity-scoped operations rather than automatically injecting an entity header.
