# Fable RC103 — Parent managed-account selection and invitation integrity

## Dependency and scope
- Base: Flutter/main RC102 `3ec4af99c0fd4ea59a049ad5162abe58ac594431`.
- RC101 and RC102 are merged and preserved; this patch does not change Auth 40/40 accounting, Backend RC67 source or P6 live E2E requirements.
- The app-wide FableManagedEntityStore is the selected-entity source of truth. A local widget selection is only a UI hint; it cannot authorize a mutation.

## Gap closed
The parent `FableManagedAccountsPage` held `_selected` locally. When another route changed the app's managed-entity context, this widget could continue to show an earlier selection or proceed through an invitation dialog against the old entity. RC102 had already protected the nested members page, but not the parent invitation operation.

## Changes
- Bind the parent to `FableManagedEntityScope` when available and listen for selected entity changes.
- Require identical selected object and exact Backend/identity binding before displaying chosen-entity actions.
- When a remote route or logout clears/switches the store, discard the parent local selection, any pending lifecycle OTP and stale selected-entity UI.
- On a Backend-confirmed activation, activate the same selection object in the shared store only if no other route changed the context while the activation request was in flight. A late A activation cannot overwrite a newer B selection. Preserve the optional `onActivated` callback. On entity creation/edit/lifecycle completion, clear shared context as well as local widget state.
- An invitation dialog retains the initial store selection revision. After every confirmation and before POST, it checks that the same store, revision and selected object remain active. A→B→A cannot reuse the old dialog.
- Other Backend keeps its independent authentication and selection contract; never infer Fable routes or roles.

## Mock regression evidence
`packages/features/fable_profile/test/managed_parent_selection_rc103_test.dart` covers:
1. Selected Fable entity is confirmed in app store after activation.
2. A→B→A during an open invitation dialog produces no invitation POST and no stale action buttons.
3. External selection clear immediately removes chosen-entity admin controls.
4. A slow Backend activation response cannot overwrite another route's newer selection.
`test/managed-access-context-wizard.test.mjs` checks additional parent scope and invite rules.

## Remaining
- Real Backend/DB/device E2E still P6; no production certification.
- Business-feature Wizard scaffolds must explicitly opt into `executeUsingStore` for managed scopes.
- P2 remaining reviews are focused on owner lifecycle and scoped permission transitions; do not restart Auth.
