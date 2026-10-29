---
name: software-engineering
description: Root engineering router for the supported stack. Load for any coding, architecture, debugging, refactoring, build, deployment, testing, UI/UX, Next.js, NestJS, Prisma/MySQL, or Flutter/Dart task. It selects the smallest set of domain skills and enforces senior-plus engineering behavior.
---

# Software Engineering — Root Router

This is the mandatory first user skill for software-development work in this distribution.

## Active stack

Enforce this distribution's stack contract directly:

- Backend: NestJS + TypeScript + Prisma ORM + MySQL.
- Web: Next.js + React + TypeScript.
- Mobile: Flutter + Dart, with Gradle/Xcode integration required by Flutter.
- Infrastructure: DevOps skill.
- Verification: Tester skill.
- Security: hierarchical cybersecurity skill.

Do not introduce a competing primary framework, ORM, database, or mobile framework without explicit user instruction.

## Instant routing

After reading this file, load only the matching branches:

| Task signal | Required branch |
|---|---|
| NestJS, controller, DTO, guard, service, Prisma, MySQL, API, auth, business logic | `backend/SKILL.md` |
| Next.js, React web page, App Router, Server Component, SEO, web frontend | `frontend-web/SKILL.md` |
| Flutter, Dart, Android/iOS app, pubspec, widget, Riverpod/BLoC, Gradle, Xcode | `mobile-flutter/SKILL.md` |
| Docker, Linux, Nginx, CI/CD, deployment, server, release pipeline, observability, backup | `devops/SKILL.md` |
| unit/integration/e2e/regression/performance test, QA, test plan | `tester/SKILL.md` |
| UI quality, UX flow, accessibility, design-system work | `ui-ux/SKILL.md` + the relevant frontend/mobile branch |
| responsive/adaptive layout, multiple screen sizes, tablet/iPad/desktop/mobile, orientation, overflow | `responsive-adaptive-ui/SKILL.md` + the relevant frontend/mobile branch + `tester/SKILL.md` when validating |
| cleanup, refactor, maintainability, architecture smell, code review | `code-quality/SKILL.md` + the relevant implementation branch |
| Google Play/App Store release, policy, privacy declaration, store rejection, mobile release readiness | `release-compliance/SKILL.md` + `mobile-flutter/SKILL.md` |
| security audit, vulnerability, secrets, auth security, hardening, pentest | `/mnt/skills/user/cybersecurity/SKILL.md` + matching security branch + implementation branch |

If a task spans domains, combine branches. Do not make the user manually choose a skill.

## Senior-plus reasoning standard

Before changing code, establish the relevant system model:

1. Identify the request, acceptance criteria, and constraints.
2. Inspect the actual repository and current conventions before proposing rewrites.
3. Trace the data/control flow end to end across UI, state, API, service, database, infrastructure, and external systems as relevant.
4. Identify invariants, trust boundaries, failure modes, concurrency risks, data-migration risks, and backward-compatibility constraints.
5. Choose the smallest robust design that fits the existing architecture.
6. Implement with explicit validation, typed contracts, deterministic error handling, and no hidden side effects.
7. Verify with the strongest available evidence: formatter, static analysis, type checker, unit/integration/e2e tests, build, and targeted runtime checks.
8. Review the diff for regressions, security, performance, observability, accessibility, release policy, and rollback.

Never claim a fix is complete merely because the code looks plausible.

## Evidence hierarchy

Prefer, in order:

1. actual repository behavior and tests,
2. official framework/platform documentation,
3. compiler/linter/build output,
4. reproducible runtime evidence,
5. reasoned inference clearly marked as such.

For version-sensitive issues, use current official documentation rather than memory.

## Architecture behavior

Do not over-engineer small features, but do not put business rules in presentation layers for convenience. Preserve clear boundaries:

- UI/presentation handles rendering and interaction.
- Application/use-case layer coordinates business operations where complexity warrants it.
- Domain/business rules remain framework-light where practical.
- Backend services enforce authorization and authoritative validation.
- Prisma/data access handles persistence, not business policy.
- Infrastructure concerns remain replaceable and observable.

## Change discipline

- Respect current project patterns unless they are demonstrably harmful.
- Refactors must preserve behavior unless behavior change is requested.
- Avoid broad rewrites when a localized change is safer.
- No blind dependency upgrades.
- No broad `any`, `dynamic`, ignored errors, silent catches, or disabling linters to make builds pass.
- No credentials, signing secrets, or production tokens in source.
- Destructive migrations require backup/rollback thinking.
- Mobile release work must include store-compliance preflight.
- Every user-facing Next.js or Flutter screen must satisfy responsive/adaptive UI requirements across its supported viewport/device classes; load `responsive-adaptive-ui/SKILL.md` for implementation or review.
