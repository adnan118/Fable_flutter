# RC99 — P2: managed-role demotion and context revocation

## Verified checkpoint

- Prior Flutter/main RC98: `ca1a02a03a06b9f221ca41101dc1fb0878960f71`, validated by Flutter packages, Android APK and iOS Simulator PR CI.
- Authentication 40/40 source ownership remains preserved (31 Mobile / 7 Web / 2 Admin); **live E2E remains not accepted**.
- Backend managed-accounts listMine contains only the requesting user's membership rows (`memberships[{access,active}]`) and activation returns the effective access for the logged-in user.
- Backend RC66 continues to enforce membership on scoped operations. No Backend runtime code modified.

## Fixed source gap

Previously, an active selected entity remained selected after `listMine` refresh provided the same entity ID, *even if the current user had lost MANAGER permissions or was demoted to VIEWER*.

New behavior:
- Parse only valid current-user membership rows as `effectiveAccess` (OWNER / MANAGER / VIEWER), and reject unknown, malformed or conflicting active memberships.
- On explicit list refresh, retain a selection only if the selected entity is ACTIVE **and the current user's exact selected role is unchanged**.
- Clear the project-wide selected context when user identity changes, a membership refresh fails, or role/entity state differs. No privileged UI stays selected from stale membership.
- Other Backend and global permissions remain independent; a selected entity is UI context, not authorization.
- A role change cannot bypass server permission guards, even when UI has not yet refreshed.

## Tests

`packages/features/fable_profile/test/managed_role_revocation_rc99_test.dart` includes membership parsing, duplicate/forged role rejection, role-demotion UI invalidation, and HTTP 403 membership refresh clearing.

## Pending P2

- In-flight scoped request invalidation when switching between different managed entities of the same logged-in user.
- Dynamic Access Control permission snapshot refetch on 403/foreground and managed selection changes, without stale cache reuse.
- Owner-only member removal/invitation APIs across failure and conflict scenarios; additional admin-role operations are not ordinary user mobile routes.
- Production database/device E2E remains P6 and must not be labeled CI-passed.

RC99 is a focused source safety fix; do not change Auth counts, Backend versions or production readiness based on this review.
