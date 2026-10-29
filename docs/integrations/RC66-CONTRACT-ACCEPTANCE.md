# Fable Flutter RC49 — Contract integration acceptance (source-only)

This generated Flutter repository can successfully compile and test while still being a **starter fixture**. A successful Flutter CI run must never be described as a live Backend RC66 integration test.

## Two separate gates

```bash
# Run from the generated Flutter application root.
node --test test/contract-acceptance.test.mjs
node tools/verify-fable-contract.mjs --mode source

# After choosing a real generated Backend project and importing its verified
# contract/handoff/OpenAPI/mobile core files, pin its actual project ID:
node tools/verify-fable-contract.mjs --mode project --expected-project-id YOUR_ACTUAL_BACKEND_PROJECT_ID
```

The **source** gate checks JSON formats, the Backend RC66 canonical SHA-256 of `contract.json`, the handoff SHA-256, the mobile core operation digest, project identity agreement, security metadata, OpenAPI methods/routes and overlapping operation IDs. It accepts a structurally sound `test-project` as a **test fixture only**, with `projectBound=false` and `productionReady=false`.

The **project** gate requires a caller-supplied, exact project identity and refuses the known starter fixture `test-project`/`fable-test`. An intentionally Auth-only project with zero business operations is permitted if its source and identity are genuine: zero operations alone must not be treated as a defect. This is still an *offline binding check*, not proof that a server, DB, provider or device actually works.

## RC66 overlapping Auth operations

Backend RC66 may export some core Auth routes in both the OpenAPI paths and the Mobile Core catalog. `FableContract.fromMaps` reconciles an overlapping ID **only** when method, path and public/private authentication are exactly the same. Different metadata fail closed; repeated IDs *within* either catalog remain invalid. The parsed OpenAPI operation remains authoritative.

## Required next steps

1. Identify which generated Backend project the Flutter app belongs to; never re-label the sample fixture as a real project.
2. Export the four contract artifacts from that exact generated Backend project and import through the generator's verified contract flow (`--dry-run` first).
3. Pin the actual project ID with `--mode project` and rerun tests.
4. Check real authentication, 2FA, session rotation, authorization, offline replay, notifications, media, device APIs and database in separately authorized live environments.
5. Do not mark Production ready without the full release strict evidence. **Production NO-GO** remains appropriate now.

The CLI does not fetch URLs, does not send tokens and does not modify contract assets.
