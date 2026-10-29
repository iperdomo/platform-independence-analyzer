# Report Template

The shape of `PLATFORM-DEPENDENCY-ANALYSIS.md`. Tier 1 writes it as a draft,
the Tier 2 verifier edits the finding headings in place, and the main agent
finalizes it. `scripts/report.py check` enforces the structure below, so keep
it exact.

## Rules for the draft

- **Finding headings carry ID, severity and status on one line**:
  `### [PDA-NNN] [<Severity>?] [UNVERIFIED] <title>`. Claim IDs run `PDA-001`,
  `PDA-002`, ... in discovery order, are assigned after aggregation (T5), and
  are never renumbered. The `?` marks a tentative Tier 1 severity.
- After verification the heading reads `[<Severity>] [CONFIRMED]`,
  `[<Severity>] [ADJUSTED: <reason>]`, `[OK] [ADJUSTED: <reason>]` or
  `[N/A] [REJECTED: <reason>]` (R4a). Reasons contain no square brackets.
- Every finding has a `Claimed role:` line and a `Locations:` line. The
  verifier adds a `Verification note:` line.
- Cite with the full path every time: `src/pay/order.ts:42`, never `order.ts:42`
  or a bare `:42` continuation. `scripts/linkify.py` links only full paths, and
  `report.py check` rejects bare continuations.
- Findings from Step 2's residual pass state their license basis in the
  `Problem:` sentence ("`@sentry/node` is a client for Sentry's hosted service,
  licensed FSL, not OSI-approved"), so Tier 2 checks the reasoning instead of
  re-deriving the license from memory.
- Leave the three `_... pending verification._` placeholders alone. The
  severity table, Executive Summary and File Index depend on the verdicts, so
  they are written at Finalize, never in the draft.
- `Files scanned:` is computed with `rg --files <repo-root> | wc -l` (respects
  `.gitignore`; `git ls-files` returns 0 when nothing is tracked yet).
- `Coverage limits:` names anything structural the audit could not see:
  uninitialized submodules, a solution file listing projects absent from disk,
  an inventory derived from imports because no manifest exists.
- With more than one sub-project, repeat the findings section per sub-project
  (`## Findings - <sub-project>`) and add a `Sub-project` column to the File
  Index. A sub-project with nothing to report keeps its section with one line:
  `No findings.`
- A `Recommended fix` names three things: the port, named after the capability
  (`PaymentService`, not `StripeService`); the vendor implementation behind
  it; and where the two are wired (composition root, DI container, factory).
  Cite a shape from `classification-rules.md` R2c when one fits, and follow R8
  for code inherited from an upstream project.
- Keep code snippets to about ten lines. Plain ASCII only.

## Template

```markdown
# Platform Dependency Analysis

- Repository: <name>
- Analyzed at: <YYYY-MM-DD>
- Files scanned: <count>
- Languages: <list>
- Sub-projects: <list, or "single project">
- Dependency inventory: manifests (N read, depths <a-b>) | imports (no manifest present)
- Coverage limits: none
- Verification: pending

## Executive Summary

_Executive summary pending verification._

_Severity table pending verification._

## Findings

### [PDA-001] [Critical?] [UNVERIFIED] Stripe called directly from the domain layer
Claimed role: domain logic with vendor call

Locations:
- `src/services/order.ts:42` direct `stripe.paymentIntents.create(...)` call
- `src/services/order.ts:88` direct `stripe.refunds.create(...)` call

Problem: <one sentence>.

Recommended fix: introduce a `PaymentService` interface, move every Stripe call into a `StripePaymentService` implementation, inject the interface into `OrderService`.

Effort: S / M / L

---

### [PDA-002] [High?] [UNVERIFIED] Mailgun across core (aggregate)
Claimed role: mixed - see representative sites

Locations: 47 files, 210 call sites in `core/` (full list in the File Index)
- `core/server/services/mail/mailgun-provider.js:31` provider implementation
- `core/server/api/endpoints/members.js:88` direct call from an API handler
- `core/frontend/services/notify.js:12` direct call from view code

Problem: <one sentence>. Severity reflects the worst site (`core/server/api/endpoints/members.js:88`).

Recommended fix: <one recommendation covering the set>.

Effort: S / M / L

---

## Acceptable Dependencies (informational)

- AWS S3 via `@aws-sdk/client-s3`: open protocol, swappable. No action.
- PostgreSQL via `pg`: open source. No action.
- `ms-rest-azure`: declared in `package.json`, zero source references - a dead declaration. Safe to remove.
- iText (AGPL-3.0 or commercial): an OSI option exists, so not a finding; a closed-source deployment needs the paid licence.

## Architecture Recommendations

1. <e.g. introduce `ports/` for interfaces; keep vendor adapters in `adapters/`>
2. <e.g. add an import-linter rule preventing vendor-SDK imports from `domain/`>

## File Index

_File index pending verification._
```

## What Finalize puts in the placeholders

- **Severity table**: rendered by `scripts/report.py finalize` from the final
  headings - Critical, High, Medium and Low only; `[OK]` and `[N/A]` are not
  counted.
- **Executive Summary**: two to four sentences - how independent the codebase
  is, the top concerns, the recommended next step.
- **File Index**: one row per file, including `[OK]` adapters and `[N/A]`
  rejections, so the reader sees what was checked and cleared:

  ```markdown
  | File | Vendor | Classification | Severity |
  |---|---|---|---|
  | src/services/order.ts | Stripe | Domain logic with vendor call | Critical |
  | src/adapters/stripe-payment.adapter.ts | Stripe | Adapter | OK |
  ```
