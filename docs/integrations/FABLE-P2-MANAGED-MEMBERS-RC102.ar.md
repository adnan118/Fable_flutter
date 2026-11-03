# RC102 — P2 managed member administration is bound to the selected entity epoch

## Baseline

- Stacked on RC101 (Flutter PR #40), which already shares the Fable authentication namespace across the app, account context, and global Access Control.
- No Backend production code changed. All managed-account operations use the explicit imported Fable contract; Other Backend remains independent.
- This is source/UI and simulated-contract coverage, **not** live Backend/DB/device E2E certification.

## Reproduced gap

The pre-RC102 members/invitations route checked only the login identity revision. An A→B switch (or A→B→A) during the same authenticated session could leave the A administration route open, with old member data and usable confirmation dialogs. A stale membership snapshot was not revalidated on foreground/resume.

## RC102 changes

1. The parent Managed Accounts page passes the app's `FableManagedEntityStore` to `FableManagedMembersPage`. Missing store, wrong Backend identity, or unrelated Auth namespace **fails closed**.
2. The members route captures the exact `selectionRevision` at creation. Every read, mutation, and rendered admin action requires the original selection object **and** unchanged revision and login identity. A→B→A cannot restore the old route.
3. A listener immediately wipes member and invitation results/cursors, stops pending UI actions, and marks the route invalid when the store's selected context changes.
4. Responses arriving after a managed switch are discarded, even when the request itself had already been sent. The Backend remains authoritative for any mutation it may already have processed.
5. Delete-member and revoke-invitation confirmation dialogs revalidate the original context **after** user confirmation and **before** the HTTP DELETE request.
6. On app resume, the page temporarily removes administration controls and reloads authenticated membership data from the verified `GET /managed-entities` contract operation. Missing, downgraded or otherwise materially changed membership/collaboration settings clear the selected entity and lock the old route.
7. A 403 or verified managed-account-not-found error from member/admin reads and actions clears the selected context. Transient failures preserve no newly asserted authorization, and the server still enforces access at every request.
8. Wizard's selected-feature integration audit now checks the members route, selection epoch guard, post-dialog confirmation guard and resume membership proof.

## Regression coverage

`packages/features/fable_profile/test/managed_members_selection_rc102_test.dart`:

- No late A member rows appear after A→B→A, even if the original selection object returns.
- No DELETE member request after switching entities inside an open confirmation.
- No DELETE invitation request after switching entities inside an open confirmation.
- A Backend-declared OWNER→VIEWER downgrade on resume clears the entity and its admin data.
- A members page without a verified selected-context store makes no network request.

## Still pending

- Actual multi-user integration against a generated Fable Backend + DB and Android/iOS devices.
- End-to-end test of permission revocation, concurrent scoped mutation, OTP/notification side effects, and app/feature scaffolds beyond the starter.
- Explicit per-feature Wizard generation of an `executeUsingStore` repository for business operations that opt into the managed entity header. No automatic header insertion into all operations.

## Merge discipline

RC102 is stacked on RC101. Do not independently merge this PR to `main` before RC101, and do not mark P2 or P6 as live verified based only on source CI.
