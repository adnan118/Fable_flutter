---
name: code-quality-refactoring
description: Cross-cutting clean-code, refactoring, maintainability, architecture-smell, and code-review skill. Load with backend, Next.js, or Flutter for cleanup and professional-quality implementation.
---

# Code Quality / Refactoring

## Principles

Optimize for correctness, readability, changeability, and operational safety—not minimum line count.

Use SOLID/DRY/KISS as reasoning tools, not rituals. Duplication can be cheaper than a wrong abstraction.

## Review dimensions

- correctness and edge cases
- cohesion and coupling
- naming and intent
- function/class/widget size
- dependency direction
- hidden side effects
- mutable shared state
- error handling
- validation boundaries
- async/concurrency hazards
- testability
- dead/unreachable code
- logging/observability
- performance hot paths
- security/privacy
- migration/backward compatibility

## Refactoring rules

- Characterize behavior with tests before risky refactors.
- Separate refactor from behavior change where practical.
- Prefer small reviewable commits/diffs.
- Delete dead abstractions rather than preserving architecture theater.
- Do not create generic helpers until a stable abstraction is visible.
- Do not convert every function to a service or every object to a pattern.

## TypeScript cleanliness

Avoid broad `any`, deep optional chaining used to hide invariants, giant DTOs, framework leakage into domain logic, and exception swallowing.

## Dart/Flutter cleanliness

Avoid giant build methods, business logic in widgets, uncontrolled globals/singletons, duplicated state sources, context use after unsafe async gaps, and unmanaged controllers/subscriptions.

## Done means verified

Clean code that does not compile, build, test, or preserve behavior is not an improvement.
