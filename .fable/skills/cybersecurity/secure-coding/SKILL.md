---
name: cybersecurity-secure-coding
description: Secure Coding branch of the cybersecurity hierarchy. Use for AppSec, source/code review, OWASP and API vulnerabilities, authentication and authorization, validation, secrets, crypto usage, mobile source security, SAST, and secure remediation.
---

# Cybersecurity / Secure Coding

## Operating rule
Treat attacker-controlled input, identity boundaries, secrets, authorization decisions, external integrations, file handling, serialization, templates, commands, and database access as explicit trust boundaries. Trace untrusted input to sensitive sinks and verify defenses rather than assuming framework defaults are sufficient.

Use this skill alongside language/framework skills when present. For example, a NestJS audit should normally combine this skill with `nestjs-expert`, `typescript-pro`, and `api-designer` where relevant.

## 4. Web Application Security

Assess and explain common web risks, including:

- OWASP Top 10 concepts
- Broken Access Control
- IDOR / BOLA
- Authentication failures
- Session fixation and weak session handling
- Injection classes
- SQL/NoSQL injection
- XSS
- CSRF
- SSRF
- Path traversal
- Unsafe file upload
- Command injection
- Template injection concepts
- Open redirects
- CORS misconfiguration
- Security header problems
- Cryptographic failures
- Insecure deserialization concepts
- Server-side request handling flaws
- Race conditions
- Business logic vulnerabilities
- Mass assignment
- Rate-limit and anti-automation weaknesses
- Cache poisoning/misconfiguration concepts
- Multi-tenant isolation failures

For each finding, record: affected component, evidence, preconditions, impact, severity, safe reproduction, remediation, and retest method.


## 5. API Security

Understand REST, GraphQL, gRPC, webhooks, and backend-for-frontend architectures. Review:

- Object-level authorization
- Function-level authorization
- Tenant isolation
- Authentication flows
- Token lifecycle
- JWT validation and key handling
- OAuth 2.0 / OIDC concepts
- Scope and audience validation
- Replay resistance
- Refresh token handling
- Rate limiting
- Enumeration risks
- Excessive data exposure
- Mass assignment
- Input validation
- Pagination abuse
- Webhook signature verification
- Idempotency
- API versioning and deprecated endpoints
- GraphQL introspection/exposure and resolver authorization

Prefer synthetic test accounts and synthetic identifiers during authorization testing.


## 6. Authentication, Authorization, and Identity

Review:

- Password storage and reset flows
- MFA and recovery paths
- Session lifecycle
- Cookie flags
- Device/session revocation
- Account enumeration
- Brute-force protections
- Role and permission design
- RBAC / ABAC
- Service accounts
- OAuth/OIDC integrations
- SSO/SAML design concepts
- Privileged access workflows
- Just-in-time and short-lived access
- Admin boundary separation

Never request or harvest real user credentials as part of a test. Use designated test accounts.


## 7. Secure Coding and Source Review

When reviewing source code:

1. Understand architecture and entry points.
2. Identify trust boundaries.
3. Identify sensitive assets and secrets.
4. Identify attacker-controlled input.
5. Trace input to sensitive sinks.
6. Review authentication and authorization checks.
7. Review file, network, process, database, and template operations.
8. Review cryptography and secret handling.
9. Review dependencies and build pipeline.
10. Rank findings and provide safer code when appropriate.
11. Re-check proposed fixes for bypasses and regressions.

Look for:

- Injection
- XSS/CSRF
- SSRF
- Path traversal
- Unsafe command execution
- Unsafe deserialization
- Authorization gaps
- Hardcoded secrets
- Weak cryptography
- Insecure randomness
- Insecure temporary files
- Race conditions
- Unsafe file handling
- Dependency vulnerabilities
- Security misconfiguration
- Information leakage
- Error-handling weaknesses

Never declare code “secure” solely because no obvious flaw was found.


## 13. Mobile Security

Understand Android and iOS security, including:

- Secure local storage
- Keychain / Keystore concepts
- Authentication and authorization
- API communication
- TLS and certificate validation
- Deep links / universal links / app links
- WebViews
- Exported components and IPC concepts
- Token storage
- Local database exposure
- Backup behavior
- Logging leakage
- Runtime permissions
- Mobile API security
- Reverse-engineering concepts in authorized labs
- OWASP MASVS / MASTG concepts

Use test builds and test accounts where possible.


## 15. Cryptography Review

Assess cryptographic use, not custom cryptographic invention. Review:

- Algorithm choice
- Key length and lifecycle
- Key storage
- Nonce/IV handling
- Randomness sources
- Password hashing
- TLS configuration
- Certificate validation
- Signature verification
- Encryption/authentication composition
- Rotation and revocation

Prefer mature, maintained libraries and standard protocols. Do not design bespoke cryptography when a standard construction exists.


## 27. Secrets and Sensitive Data

If a secret is discovered:

1. Do not echo it unnecessarily.
2. Identify where it was found.
3. Determine potential exposure path.
4. Recommend rotation/revocation when appropriate.
5. Remove it from source/history where feasible.
6. Move it to a suitable secret-management mechanism.
7. Add preventive scanning/controls.

Examples include API keys, private keys, session cookies, tokens, passwords, database credentials, signing secrets, and cloud credentials.


## Application Security Controls — Stack-Specific Rules

For the supported NestJS + Prisma + MySQL backend and Next.js/Flutter clients, apply the following controls when relevant. Do not treat any single control as a substitute for authentication, authorization, parameterized database access, contextual output encoding, or framework-safe APIs.

### Security audit events

Security-sensitive actions should emit structured, privacy-conscious audit events. Useful fields include event type, result, severity, actor/user identifier when appropriate, target/resource, request/correlation ID, normalized client IP only when operationally justified, user agent, timestamp, and non-sensitive contextual metadata. In MySQL use the native `JSON` type when structured metadata is needed; do not assume PostgreSQL-only `JSONB`.

Never log passwords, access/refresh tokens, session cookies, private keys, TOTP seeds, payment secrets, raw authorization headers, or unnecessary personal data. Logging should not materially delay user requests, but critical audit events must not be silently dropped: use a reliable bounded queue/outbox/log sink and defined failure behavior when durability matters.

### Host and canonical-origin integrity

Do not build password-reset, verification, OAuth callback, or other security-sensitive absolute URLs from untrusted `Host`, `X-Forwarded-Host`, or arbitrary proxy headers. Use an explicitly configured canonical public base URL and configure trusted proxies deliberately. If host allowlisting is used, normalize ports/case/punycode as appropriate and test behavior behind the actual reverse proxy/CDN.

### Authorization freshness and privileged actions

Never accept `role`, `isAdmin`, permissions, ownership, price, tenant, or equivalent privileged fields from a public client as authoritative. Enforce authorization server-side for every protected operation. For high-impact admin actions, use an authorization source with sufficient freshness for the risk: short-lived claims plus revocation/session/version checks, or an authoritative server-side lookup. Do not require a full database role lookup on every request unless that is an intentional performance/security tradeoff. Consider re-authentication/MFA for especially sensitive actions.

### Prisma/MySQL ownership and tenant isolation

Every user- or tenant-scoped Prisma operation must include the authenticated ownership/tenant predicate in the server-side query or must verify ownership before mutation. Do not use client-supplied IDs alone as authorization. Prefer query shapes and constraints that keep authorization and mutation atomic where practical. Do not copy ORM syntax from unrelated stacks (for example Supabase-style `.eq(...)`) into Prisma code.

### Input validation and output safety

Use NestJS DTO/runtime validation (or another project-standard runtime schema) at trust boundaries. Enforce types, enums, ranges, length/size limits, formats, and unknown-field policy. Client-side validation in Next.js or Flutter is UX only; the NestJS backend remains authoritative.

Do not solve XSS/SQLi/command injection with generic character stripping or regex signature filters. Use parameterized Prisma/database APIs, context-aware output encoding/escaping, safe template/rendering behavior, allowlists for structured inputs, and safe process/file/network APIs. Sanitize rich HTML only when the product intentionally accepts HTML and use a maintained context-aware sanitizer. Guard regexes against ReDoS with bounded input and safe patterns.

### HTTP/API boundary hardening

For state-changing JSON endpoints, enforce the expected media type and strict request size limits where appropriate. Configure CORS with explicit trusted origins when browsers call the API cross-origin. Do not treat `Origin` or `Referer` as authentication. When cookie-based authentication creates CSRF risk, use appropriate SameSite cookie settings and an established CSRF defense; token/header APIs still require normal authentication and authorization. Use security headers through framework/proxy configuration where applicable.

### Payment and webhook integrity

For payment or other high-impact webhooks, verify the provider's documented signature scheme over the exact required payload (often the raw request body), validate timestamp/replay requirements when provided, use timing-safe comparison where applicable, deduplicate provider event IDs, and make handlers idempotent. Never hard-code a generic HMAC algorithm when the provider specifies a different mechanism. Prices, currency, entitlements, discounts, and totals are calculated or verified server-side from authoritative data.

### Safe file upload handling

Do not assume that “in memory” automatically means safe. Large in-memory buffers can create denial-of-service risk. Choose bounded buffering or streaming based on file type and workload. Enforce size/count limits before expensive processing, verify content using magic bytes/content inspection in addition to declared MIME type, generate server-controlled object names, keep uploads non-executable, store outside public application paths, use quarantine/scanning for risky file classes, and prefer signed/controlled object-storage access. Re-encode images/media when that materially reduces parser/metadata risk.

### Runtime code safety

Avoid `eval`, dynamic code generation, shell concatenation, and unrestricted child-process execution. If a subprocess is genuinely required, use fixed executables/argument arrays, strict allowlists, bounded resources, and no attacker-controlled shell interpolation. Never expose server `process.env` or secrets into Next.js client bundles or Flutter artifacts.

### OWASP/WAF rule

A WAF or exploit-signature filter may be used as defense in depth, but it is not the primary application-security control and must not replace correct authorization, parameterized queries, contextual encoding, safe parsers, rate limiting, or business-logic validation. Do not implement a homemade “OWASP regex firewall” that attempts to decode and pattern-match every request.


## 31. Finding Template

For each vulnerability, prefer this structure:

**Title**  
**Status:** Confirmed / Probable / Possible / Not verified  
**Severity:** Informational / Low / Medium / High / Critical  
**Affected asset/component:**  
**Evidence:**  
**Preconditions:**  
**Technical explanation:**  
**Impact:**  
**Safe reproduction:**  
**Remediation:**  
**Retest:**  
**Residual risk:**


## 33. Confidence and Uncertainty

Never say:

- “This system is completely secure.”
- “This vulnerability definitely exists.”
- “This attack definitely works.”

unless evidence justifies the claim. Clearly distinguish observation, inference, hypothesis, and confirmation.


## Legacy references retained from the user's previous skill packs
The original Secure Code Guardian skill and its reference files are preserved under `references/secure-code-guardian/`. The previous `security-best-practices` skill is preserved as `references/security-best-practices-original.md`. Use them as supporting references; this branch is the primary operational skill.
