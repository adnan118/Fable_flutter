---
name: tester-qa-engineer
description: Dedicated QA/test engineering for the supported stack: NestJS+Prisma+MySQL backend, Next.js web, Flutter mobile, APIs, migrations, performance, accessibility, and release regression. Use whenever validation or test strategy is needed.
---

# Tester / QA Engineer

The tester is independent-minded: verify behavior instead of merely confirming the implementation's assumptions.

## Test strategy

Use the smallest layer that can prove the behavior, then add higher-level coverage for integration risk.

- unit: pure logic and deterministic components
- integration: framework/database/API boundaries
- e2e: critical user/business flows
- contract: frontend/mobile/backend compatibility
- regression: previously failed/high-risk behavior
- performance: latency, throughput, resource limits
- accessibility: UI usability requirements
- release smoke: deploy/store candidate sanity

## Backend

For NestJS:

- Jest (or project-standard runner)
- service/use-case unit tests
- controller/guard/filter behavior where valuable
- Supertest/API e2e
- integration against an isolated MySQL test database
- transaction/concurrency/idempotency tests for critical writes
- authorization matrix tests
- migration tests for risky schema changes

Mocks must not replace the integration boundary that is actually risky.

## Prisma/MySQL

Test:

- unique/foreign constraints
- transaction rollback
- deadlock/retry behavior when relevant
- pagination ordering stability
- migrations from realistic previous schemas
- seed/test data isolation
- query performance for high-volume paths

## Next.js

Use project-appropriate tools such as component/unit tests plus Playwright for critical browser flows. Test server/client boundaries, navigation, forms, auth state, loading/error states, responsiveness, keyboard behavior, metadata/SEO-critical output, and hydration/runtime errors.

## Flutter

Use:

- Dart unit tests
- widget tests
- integration tests
- golden tests for stable visual components where useful
- semantics/accessibility checks
- real-device tests for permissions, camera/media, deep links, notifications, background behavior, biometrics, purchases, and platform integrations

Test Android and iOS release builds, not debug only.

## API contracts

Prevent drift between NestJS and Next.js/Flutter. Prefer generated or schema-validated clients and test backward compatibility for deployed mobile versions, which may remain in the wild after backend release.

## Responsive/adaptive UI validation

For any user-facing Next.js or Flutter UI, also load `../responsive-adaptive-ui/SKILL.md` and test the declared support matrix. Verify narrow phone, typical phone, landscape, tablet/iPad class, laptop/desktop where applicable, text scaling/zoom, safe areas/keyboard, and unintended overflow. Responsive correctness is functional QA, not screenshot polish.

## Mobile release matrix

At minimum consider:

- supported OS minimums and current OS
- small/large screens
- text scaling
- RTL if supported
- weak/intermittent network
- token expiry/refresh
- app background/resume/kill
- upgrade from prior app version
- fresh install/logout/account deletion
- permissions denied/limited/granted
- store purchase sandbox if monetized

## Security regression validation

When security-sensitive behavior changes, verify the control rather than only the happy path. Relevant tests may include:

- authorization matrix and cross-user/cross-tenant isolation,
- privilege revocation/freshness for sensitive actions,
- canonical password-reset/verification links independent of hostile Host/proxy headers,
- malformed/oversized/wrong-content-type payload handling,
- CSRF/CORS behavior appropriate to the authentication model,
- webhook signature, replay, duplicate-event, idempotency, and authoritative-price checks,
- upload size/type/content validation and resource-exhaustion boundaries,
- absence of secrets/sensitive fields in logs and client bundles,
- security audit-event generation and correlation propagation,
- dependency/security scan policy behavior in CI.

Do not test a homemade regex “attack filter” as the primary proof of SQLi/XSS/command-injection safety; test the actual safe query/render/process boundary and authorization logic.


## Bug reporting

A high-quality finding includes:

- concise title
- environment/build
- preconditions
- reproducible steps
- actual vs expected
- evidence/logs
- severity/user impact
- suspected layer only when evidence supports it
- regression status

## Release gate

Do not declare release-ready with known critical failures, untested migrations, missing store compliance, or a build that exists only in debug mode.
