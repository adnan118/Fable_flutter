# RC293 — W5 signed owner PATCH for bounded optional text

## Source changes
The typed Fable feature planner and generator now offer a **reviewed owner-scoped PATCH** for a selected project feature operation only when the signed operation and OpenAPI independently agree on:
- `PATCH /{feature}/:id`, signed UUID `id`, one matching `{feature}.update` permission, `recordAccess=owner:<relation>` and HTTP 200 Fable object response.
- An explicit JSON object with `additionalProperties=false`, between 1 and 12 all-optional `string/text/uuid` fields and no request query, custom headers, idempotency requirement or sensitive/financial fields.
- No sensitive feature family such as Auth, Payments, Media, Access Control or notifications. Unsupported field types or managed scopes are rejected, never inferred.

Four generated layers (Domain, Application, Data, Presentation) provide a strict optional-field-only PATCH request, source-bound operation and project hash checks, a verified response DTO, identity revision fencing and a manual confirmation dialog requiring **UPDATE**. Unknown or ambiguous outcomes are not retried automatically. Empty changes, invalid UUIDs and unsuitable field values fail closed. The GET/POST, RC292 DELETE and paginated infinite-scroll flows remain separate.

## Remaining gap: optimistic concurrency
**The general Fable feature generator does NOT yet advertise/implement conditional PATCH with server-enforced If-Match or record revision checks.** This RC does not claim conflict-safe multi-editor updates or solve all write policies. A manual confirmation and server owner predicate protect against accidental/cross-owner writes but not concurrent authorized edits. Custom managed-entity PATCH/DELETE, idempotency-required writes and anything without matching signed contracts remain blocked.

## Acceptance
**Per user instruction, NO execution or device/Backend E2E tests were run for RC293**. JavaScript syntax was reviewed only. Flutter/Dart compile, schema fixtures, generated project compilation, real authorization and optimistic concurrency verification remain for the user. Existing 17 feature family flags stay `complete=false`, `liveE2EVerified=false`. W5 still has explicit remaining gaps; production NO_GO.
