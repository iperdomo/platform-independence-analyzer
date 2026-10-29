# Platform Dependency Analysis

- Repository: demo
- Analyzed at: 2026-10-29
- Files scanned: 12
- Languages: TypeScript, Python
- Sub-projects: single project
- Dependency inventory: manifests (2 read, depths 1-2)
- Coverage limits: none
- Verification: pending

## Executive Summary

_Executive summary pending verification._

_Severity table pending verification._

## Findings

### [PDA-001] [Critical?] [UNVERIFIED] Stripe called directly from the domain layer
Claimed role: domain logic with vendor call

Locations:
- `src/domain/order.ts:2` direct `stripe.paymentIntents.create(...)` call

Problem: business logic calls Stripe with no interface.

Recommended fix: pending verification.

Effort: M

---

### [PDA-002] [High?] [UNVERIFIED] OpenAI client in app/llm.py
Claimed role: service with vendor call

Locations:
- `app/llm.py:2` `OpenAI(base_url=...)`

Problem: OpenAI client constructed from an env-var endpoint.

Recommended fix: resolve the endpoint first.

Effort: S

---

### [PDA-003] [Low?] [UNVERIFIED] Stripe mentioned in a comment
Claimed role: script

Locations:
- `scripts/seed.ts:3` comment naming Stripe

Problem: possible vendor usage in a script.

Recommended fix: none.

Effort: S

---

## Acceptable Dependencies (informational)

- PostgreSQL via `pg`: open source. No action.

## Architecture Recommendations

1. Introduce `ports/` for vendor-facing interfaces.

## File Index

_File index pending verification._
