# Platform Dependency Analysis

- Repository: demo
- Analyzed at: 2026-10-29
- Files scanned: 12
- Languages: TypeScript, Python
- Sub-projects: single project
- Dependency inventory: manifests (2 read, depths 1-2)
- Coverage limits: none
- Verification: completed 2026-10-29

## Executive Summary

Mostly independent one; one Critical Stripe coupling in the domain layer.

| Severity | Count |
|---|---|
| Critical | 2 |
| High | 0 |
| Medium | 1 |
| Low | 0 |

## Findings

### [PDA-001] [Critical] [CONFIRMED] Stripe called directly from the domain layer
Verification note: `src/domain/order.ts:2` calls the SDK; no interface anywhere.

Locations:
- `src/domain/order.ts:2` direct `stripe.paymentIntents.create(...)` call

Problem: business logic calls Stripe with no interface.

Recommended fix: introduce a `PaymentService` port and a Stripe adapter.

Effort: M

---

### [PDA-002] [Medium?] [ADJUSTED] OpenAI client in app/llm.py
Claimed role: service with vendor call
Verification note: `app/llm.py:2` reads LLM_BASE_URL with no default; R5 ladder did not resolve it.

Locations:
- `app/llm.py:2` `OpenAI(base_url=...)`

Problem: OpenAI client constructed from an env-var endpoint.

Recommended fix: resolve the endpoint first.

Effort: S

---

### [PDA-001] [Low] [REJECTED: comment] Stripe mentioned in a comment
Claimed role: script
Verification note: `scripts/seed.ts:3` is a comment.

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

| File | Vendor | Classification | Severity |
|---|---|---|---|
| src/domain/order.ts | Stripe | Domain logic with vendor call | Critical |
| app/llm.py | OpenAI | Service with vendor call | Medium |
| scripts/seed.ts | Stripe | Comment | N/A |

### [PDA 4] malformed
