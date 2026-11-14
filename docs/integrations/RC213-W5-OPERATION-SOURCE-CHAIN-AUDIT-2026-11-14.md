# RC213 — W5 actual feature-operation source trace gate

**2026-11-14.** W5 is now an executable source-trace workflow. It is **not** a live Flutter application test, a real Backend project sign-off, nor full W5 feature completion.

## Root-cause fixes
Previously `tools/audit-selected-feature-integration.mjs` checked whether an evidence file **exists**, but did not reject symbolic/hard links or ensure all source evidence remained within the selected project. A selected feature could have a claimed `frontendFile` or `testFile` which was a symlink to a file elsewhere; the audit could count the path while following the link when reading managed scope evidence. Existing `checkedFile` and all managed-scope source/test reads now use `tools/w5-safe-source-evidence.mjs`: explicit path checking, `lstat` on components, nofollow/nonblocking final open, regular-file and single-link checks, 8 MiB maximum and bounded relative paths.

## Actual per-operation W5 evidence
New `tools/w5-feature-flow-audit.mjs` reads the **project's** selected features, Backend kind, current Fable/External operation contract, explicit `.fable/feature-integration-requirements.json` and `.fable/w5-operation-flows.json` with safe path reads.

The selected feature set is derived from the existing W0 feature-selection union (built-in selections, separately registered custom features, and enabled Flutter-owned decisions). Unsafe symlinked selection manifests and requirements for unselected features are rejected.\n\nFor each selected feature it refuses:
- Missing full declared Backend scope (including the **second/third operation** never mentioned in the UI trace); any extra undocumented Backend operation; server-owned Auth pretending to be client-only.
- Missing/stale `operationId`, HTTP method/path or external feature role binding; a Fable operation absent from the current Fable contract; provider Webhook or unauthenticated external mutation being presented as a mobile API.
- Missing operation-level source proof chain `repository -> state -> ui -> navigation -> test`. Every stage must have a real safe file and declared marker; the next file must contain the preceding stage's marker. Repositories must reference the actual operation ID and tests the UI marker or operation ID.
- Missing typed request/response DTO source evidence, error cases or permission denial cases for backend operations.
- Unexpected local HTTP requests for Flutter-only features: these use explicit `method:LOCAL` and `path:local:...`, never invented Fable routes.

The Wizard now includes an independent, non-authoritative `w5OperationFlowAudit` summary after applying setup. Source-only traces may be PASS but **`liveE2EVerified=false`**, **`productionApproved=false`**. Other Backend stays pending until an independently verified API catalog and feature bindings exist. Fable source verification requires a separately supplied real project ID and Backend contract SHA-256; an installed fixture or self-provided hash is not a release pin.

## Required W5 manifest schema (illustrative, not a completed feature)
Place `.fable/w5-operation-flows.json` inside the generated Flutter project:

```json
{
  "schemaVersion": 1,
  "kind": "fable.w5-operation-flows",
  "projectId": "your-real-project-id",
  "backendKind": "fable",
  "contractHash": "<64 lowercase hexadecimal chars from independently verified Backend export>",
  "flows": [
    {
      "feature": "auth",
      "mode": "backend",
      "operationId": "auth.change-password",
      "method": "POST",
      "path": "/auth/change-password",
      "permission": "authenticated",
      "stages": {
        "repository": {"path": "packages/fable_core/lib/src/fable_auth_gateway.dart", "marker": "changePassword"},
        "state": {"path": "packages/features/fable_auth/lib/src/change_password_page.dart", "marker": "_submit"},
        "ui": {"path": "packages/features/fable_auth/lib/src/change_password_page.dart", "marker": "FableChangePasswordPage"},
        "navigation": {"path": "lib/src/app.dart", "marker": "FableChangePasswordPage"},
        "test": {"path": "packages/features/fable_auth/test/change_password_page_test.dart", "marker": "FableChangePasswordPage"}
      },
      "dto": {
        "request": {"path": "packages/fable_core/lib/src/fable_auth_gateway.dart", "marker": "currentPassword"},
        "response": {"path": "packages/fable_core/lib/src/fable_auth_gateway.dart", "marker": "changed"}
      },
      "errorCases": ["401", "409"],
      "permissionCases": ["unauthenticated-denied"]
    }
  ]
}
```

This is deliberately an **illustrative template, not verified W5 evidence**. If the feature requires additional operations, every required operation must be declared in `.fable/feature-integration-requirements.json` and have its own valid trace; missing navigation/DTO/test references are reported as BLOCKED. The above example should not be applied without checking source, current contract and independent project pins. The source scope file must be `{schemaVersion:1,kind:"fable.feature-integration-requirements",features:{auth:{needsBackend:true,operations:[{operationId:"auth.change-password",method:"POST",path:"/auth/change-password"}]}}}` for an Auth-only demonstration; real Auth has more required operations.

## Run
```sh
cd Fable_flutter
npm run test:w5:source-flows
npm run wizard:w5:audit
# On a truly generated Fable Flutter project with an independent Backend export SHA:
node tools/run-w5-feature-flow-audit.mjs --root /path/to/flutter-project \
  --expected-project-id YOUR_PROJECT_ID \
  --expected-contract-hash 64_LOWERCASE_HEX_SHA256 --json
```

The source gate returns exit code 2 on missing flow evidence, unbound required operations, unsafe evidence paths or missing independent Fable contract pins. Running `npm run wizard:w5:audit` on the starter may reasonably return 2; that is the intended fail-closed result. This gate does not run a Flutter build or invent backend credentials.

## Verified in this turn
**19/19 isolated V8 functional/source-wiring assertions PASS** against exact current GitHub branch source blobs, including real scope parity logic, method drift, missing state links, DTO proof, unbound external role, local-only Deeplinks, server Auth isolation, duplicates, empty selection and Wizard import, and syntax parses. **22 new Node regression tests authored**, including real-filesystem symlink cases; a complete local Flutter checkout was unavailable and therefore `node --test` and Dart analyzer/device E2E were **not executed** here. No GitHub Actions assumptions.

**Remaining:** actual W5 flows for all selected operations/features, real Backend/Flutter contract and 12 W4 project examples, 17 feature families' live E2E, W6–W8 release/provider/device conditions and 82 tracked W0 gap/evidence items. No false production GO.
