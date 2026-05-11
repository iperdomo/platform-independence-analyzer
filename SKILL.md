---
name: platform-independence-analyzer
description: Audit a code repository for direct dependencies on closed-source or proprietary services (Firebase, Google Maps, Stripe, Twilio, SendGrid, MongoDB, vendor SDKs, cloud-specific functions, etc.) that lack an abstraction layer. Use when the user asks to evaluate platform independence, vendor lock-in, proprietary-dependency coupling, swappability of services, missing adapter/repository/port layers, or to produce a PLATFORM-DEPENDENCY-ANALYSIS.md report. Triggers on phrases such as "platform independence", "vendor lock-in", "proprietary dependency audit", "check for closed-source dependencies", "are we coupled to <vendor>", "can we swap <vendor>".
---

# Platform Independence Analyzer

Audit a repository for direct coupling between business logic and proprietary or closed-source services. The deliverable
is a `PLATFORM-DEPENDENCY-ANALYSIS.md` report that names every coupling site by `file:line`, classifies its severity,
and recommends a concrete abstraction.

## Core Definitions

- **Platform Independence**: domain or business code makes no direct API call into a proprietary SDK or service. All
  proprietary calls flow through an abstraction: adapter, port, repository, provider, gateway.
- **Direct dependency (violation)**: a domain or business-layer file imports a vendor SDK or hits a vendor-specific URL.
- **Indirect dependency (acceptable)**: domain code uses an interface or abstract type. Only a designated adapter or
  repository file imports the vendor SDK.

**Scope of this audit**: this skill assesses *platform independence* (vendor lock-in risk), not architectural quality or
robustness. Direct dependencies on OSI-approved open-source libraries, modules, or services are **acceptable** and must
not be flagged, even when imported straight from domain code with no abstraction layer. Whether such code *should* be
abstracted for testability, modularity, or clean-architecture reasons is out of scope here. A library qualifies if it is
released under an [OSI-approved license](https://opensource.org/licenses) (MIT, Apache-2.0, BSD, GPL, MPL, etc.); when a
license is unclear, treat it as proprietary and flag it. Only proprietary, closed-source, or vendor-controlled SaaS
dependencies count as findings.

The whole audit is the question "if we had to replace vendor X tomorrow, which non-adapter files would change?" — where
"vendor X" is a *proprietary* dependency. Open-source dependencies can always be forked, self-hosted, or replaced
without vendor cooperation, so they do not create lock-in. Every non-adapter file touching a proprietary SDK is a
finding.

## Workflow

Execute these steps in order. Within a step, batch independent tool calls in parallel.

### Step 1 — Establish scope

- Project root defaults to the current working directory unless the user says otherwise.
- Identify languages by reading manifest files in parallel: `package.json`, `pyproject.toml`, `requirements.txt`,
  `pom.xml`, `build.gradle`, `go.mod`, `Gemfile`, `composer.json`, `Cargo.toml`.
- Note the architectural style if visible from the directory layout (layered, hexagonal/ports-and-adapters, clean, MVC).
  This determines what "domain" means for Step 4.
- Always exclude these directories from searches: `node_modules`, `vendor`, `dist`, `build`, `target`, `.git`, `.venv`,
  `__pycache__`, `coverage`, `.next`, `.cache`, generated code directories, and lock files.

### Step 2 — Inventory declared proprietary dependencies

Read each manifest file and list every dependency matching a known proprietary service from
`references/dependency-patterns.md`. This is the candidate list that drives Step 3. If a candidate is not declared in
any manifest but appears in source (e.g. via direct HTTP), still include it.

### Step 3 — Locate usage sites

For every candidate vendor, run a targeted ripgrep in parallel via Bash or the Grep tool. Use the patterns in
`references/dependency-patterns.md` as a starting point. Examples:

- Firebase: `rg -n "from ['\"]firebase|firebase-admin|firestore\\(" --glob '!node_modules' --glob '!dist'`
- Google Maps: `rg -n "@googlemaps|google\\.maps|googlemaps\\.Client" --glob '!node_modules'`
- Stripe: `rg -n "from ['\"]stripe['\"]|import Stripe|stripe\\." --glob '!node_modules'`
- MongoDB: `rg -n "MongoClient|mongoose|pymongo|com\\.mongodb" --glob '!node_modules'`
- Twilio / SendGrid: `rg -n "twilio|sendgrid|@sendgrid" --glob '!node_modules'`
- AWS non-S3: `rg -n "aws-sdk|boto3|@aws-sdk" --glob '!node_modules'` (then filter S3-only files out in Step 6)

Record every hit as `path:line` with the surrounding context, then group hits by file.

### Step 4 — Classify each file

For each file with at least one hit, decide its role:

| Role | Heuristic | Treat as |
|---|---|---|
| Adapter / Provider / Repository / Gateway | File implements an interface or abstract class AND its name or directory marks it as the vendor's wrapper (e.g. `stripe-payment.adapter.ts`, `adapters/`, `infrastructure/`, `repositories/`). | Acceptable |
| Composition root / Bootstrap | Wires services into a DI container or factory at startup (e.g. `container.ts`, `main.py`, `bootstrap.js`, `wire.go`). | Acceptable |
| Configuration | Reads vendor config from env vars; does not invoke the SDK. | Acceptable |
| Domain or business logic with vendor call | Lives under `domain/`, `core/`, `services/`, `usecases/`, `controllers/`, `handlers/`, `app/`, etc. and imports the SDK directly. | Violation |
| Test using real SDK | Integration test against live vendor. | Low — flag |
| Test mocking the SDK directly | Unit test mocks the vendor instead of an interface. | Medium — coupling leaks into tests |

A file is an adapter only if both conditions hold: (a) it implements an interface or abstract class for that capability,
and (b) it is the *only* place that vendor SDK is referenced for that capability. A file named `*-adapter.*` that still
has callers importing the SDK elsewhere is not a real adapter.

### Step 5 — Assign severity

- **Critical**: vendor SDK called from the domain layer with no interface anywhere; multiple call sites.
- **High**: vendor SDK called from a service layer that lacks an interface; concentrated in one or two files.
- **Medium**: an interface exists but leaks vendor types through its public surface (e.g. method returns `Stripe.PaymentIntent`), or unit tests mock the SDK directly.
- **Low**: scripts, CLIs, migrations, or integration tests that import the SDK directly while production code is properly abstracted.

### Step 6 — Recognize acceptable patterns

Do not flag any of the following:

- **AWS S3** specifically — open S3 protocol, swappable with MinIO, Ceph, Garage. Other AWS services remain in scope.
- **Standard protocols**: HTTP, HTTPS, SMTP, IMAP, OAuth, OIDC, gRPC, WebSockets, MQTT.
- **OSI-approved open-source datastores**: PostgreSQL, MySQL, MariaDB, SQLite, Cassandra, BSD-era Redis, Valkey.
- **A vendor SDK imported only inside its dedicated adapter file** (see Step 4).
- **Type-only imports** (`import type ...`) of vendor types when domain types are used everywhere else. If a vendor type
  leaks through a public interface, downgrade to Medium rather than ignore.

When in doubt, flag and let the user decide; document the ambiguity in the finding.

### Step 7 — Generate the report

Write `PLATFORM-DEPENDENCY-ANALYSIS.md` at the project root. Cite every claim with `path:line`. Use the template below.

## Report Template

```markdown
# Platform Dependency Analysis

- Repository: <name>
- Analyzed at: <YYYY-MM-DD>
- Files scanned: <count>
- Languages: <list>

## Executive Summary

<Two to four sentences: how independent is this codebase, the top concerns, and the recommended next step.>

| Severity | Count |
|---|---|
| Critical | N |
| High | N |
| Medium | N |
| Low | N |

## Findings

### [Critical] <Vendor> directly used in domain layer

Locations:
- `src/services/order.ts:42` direct `stripe.paymentIntents.create(...)` call
- `src/services/order.ts:88` direct `stripe.refunds.create(...)` call

Problem: <one sentence>.

Recommended fix: introduce a `PaymentService` interface (see `references/abstraction-examples.md`), move every Stripe call into a `StripePaymentService` implementation, inject the interface into `OrderService`.

Effort: S / M / L

---

### [High] <next finding>
...

## Acceptable Dependencies (informational)

- AWS S3 via `@aws-sdk/client-s3`: open protocol, swappable. No action.
- PostgreSQL via `pg`: open source. No action.

## Architecture Recommendations

1. <e.g. introduce `ports/` for interfaces; keep vendor adapters in `adapters/`>
2. <e.g. adopt a DI container or factory>
3. <e.g. add an ESLint or import-linter rule preventing vendor-SDK imports from `domain/`>

## File Index

| File | Vendor | Classification | Severity |
|---|---|---|---|
| src/services/order.ts | Stripe | Domain logic with vendor call | Critical |
| src/adapters/stripe-payment.adapter.ts | Stripe | Adapter | OK |
...
```

## When to Read the References

- Read `references/dependency-patterns.md` at the start of Step 3 to retrieve the full pattern list and detection keywords for the languages found in Step 1.
- Read `references/abstraction-examples.md` while drafting "Recommended fix" sections in Step 7, so suggested code matches the shape (interface + implementation + DI wiring) appropriate to the target language.

## Output Discipline

- The report is the deliverable. Do not modify code unless the user explicitly asks for remediation in a follow-up.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- Keep each code snippet in the report to roughly ten lines.
- If the repo is clean (no violations), still emit the report so the user has documentation of that fact and the acceptable dependencies.
- Plain ASCII only. No emojis.
