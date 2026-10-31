# Fable Backend → Flutter / Wizard: Session policy handoff

## Authoritative sources

1. **Build / Wizard**: The verified Backend `contract.json` contains `core.auth.sessionPolicy` with `mode` (`single` or `multi`), `maxActive` (0 = unlimited), `overflow`, `runtimeEndpoint` and `runtimeAuthoritative=true`. No Flutter-side policy is chosen independently.
2. **On-device runtime**: Flutter calls **GET /auth/session-policy** through the *imported verified operation* `auth.session-policy`. The actual running Backend replies `mode`, `maxActive`, `overflow` and `onePerInstallation`. Runtime takes precedence if deployment environment changed after export.
3. **Enforcement**: Backend alone creates and revokes `AuthSession`; displaying a mode in Flutter never enforces that mode.

## Wizard integration

After importing the Backend's `contract.json`, `flutter-handoff.json`, `mobile-core-operations.json` and `openapi.json`, run:

```bash
node tools/read-session-policy.mjs
```

The command validates the local exported contract and prints JSON, e.g.:

```json
{
  "mode": "multi",
  "maxActive": 0,
  "overflow": "revoke-oldest",
  "runtimeEndpoint": "/auth/session-policy",
  "runtimeAuthoritative": true,
  "allowsMultipleSessions": true
}
```

The wizard must consume that output as a **read-only project decision**. Never show a choice to override an imported backend's session mode. With another Backend, require its own explicit session contract. If the policy is missing or contract validation fails, mark it **unknown/unavailable**; do not default to `multi`.

The standard source verifier `node tools/verify-fable-contract.mjs --mode source` also returns a `sessionPolicy` field when present and valid. This is a local integrity/compatibility check, **not** evidence of connectivity to a deployed production Backend; project binding requires independent project identity + exported hash checks.

## Flutter runtime

```dart
final exportedPolicy = contract.sessionPolicy; // verified build-time hint; nullable for legacy exports
final effectivePolicy = await authGateway.loadSessionPolicy(); // current Backend policy
if (effectivePolicy.allowsMultipleSessions) {
  // Present multi-session devices/revoke UI when the corresponding operations exist.
} else {
  // Single-session explanation; do not expose multi-session-only controls.
}
```

A network error, missing route, or malformed response is **not** permission to assume `multi`. Treat policy as unavailable, use only safe UI, and leave Backend enforcement in place. The UI must not infer a policy from the number of currently active sessions, and should not treat `multi(maxActive:1)` as supporting concurrent devices.

## Required regression coverage

- `single`: new login revokes older sessions.
- `multi, maxActive=0`: no session count restriction.
- `multi, maxActive=N`: `revoke-oldest` vs `reject-new` behavior.
- `AUTH_SESSION_ONE_PER_INSTALLATION=true`: same installation replaces its previous session.
- Changes to server environment between exports are reflected by the runtime policy.
- A legacy export with no policy remains unknown; no guessing.
- Logout and session revocation immediately invalidate subsequent authenticated requests.

**Rollout:** Merge and deploy Backend first, re-export and import the matching Flutter contract, then build the mobile app. Existing starter fixture `test-project` is not a production backend binding.
