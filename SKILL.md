---
name: platform-independence-analyzer
description: Audit a code repository for direct dependencies on closed-source or proprietary services (Firebase, Google Maps, Stripe, Twilio, SendGrid, MongoDB, LLM/AI APIs like OpenAI, Anthropic, Gemini, Cohere, Mistral, vendor SDKs, cloud-specific functions, etc.) that lack an abstraction layer. Use when the user asks to evaluate platform independence, vendor lock-in, proprietary-dependency coupling, swappability of services, missing adapter/repository/port layers, or to produce a PLATFORM-DEPENDENCY-ANALYSIS.md report. Triggers on phrases such as "platform independence", "vendor lock-in", "proprietary dependency audit", "check for closed-source dependencies", "are we coupled to <vendor>", "can we swap <vendor>", "are we locked into OpenAI", "LLM/AI vendor lock-in".
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

**The service's license matters, not the client library's.** Judge lock-in by the backing service or protocol a
dependency binds you to, not by the license of the SDK on npm/PyPI. Example: `mongoose` is MIT-licensed, but it exists to
talk to MongoDB, whose server is SSPL (not OSI-approved) — so a `mongoose` coupling is a finding. Conversely, an
MIT-licensed Postgres driver binds you only to an open protocol, so it is Acceptable. When a permissively licensed client
is just a wrapper around a proprietary SaaS, flag it.

The whole audit is the question "if we had to replace vendor X tomorrow, which non-adapter files would change?" — where
"vendor X" is a *proprietary* dependency. Open-source dependencies can always be forked, self-hosted, or replaced
without vendor cooperation, so they do not create lock-in. Every non-adapter file touching a proprietary SDK is a
finding.

## Workflow

This audit runs in **two tiers**:

- **Tier 1 — Scan (draft)**: a cheap, low-judgment mechanical pass (Steps 1-7). It inventories manifests, greps for vendor
  usage, and writes a *draft* `PLATFORM-DEPENDENCY-ANALYSIS.md` where every finding carries a stable claim ID and
  `Status: UNVERIFIED`. Classification and severity are *tentative* here, assigned from name/path heuristics only — no
  call-site reading, no cross-file analysis.
- **Tier 2 — Verify**: a fresh-context subagent confirms, adjusts, or rejects each claim using call-site and cross-file
  analysis, then the main agent finalizes the report (recomputes the severity table, flips the header to
  `Verification: completed`). Tier 2 is defined in its own section below.

The classification rules (Steps 4-6) are the authoritative rulebook for *both* tiers: Tier 1 applies only their name/path
heuristics to produce tentative labels; Tier 2 applies them in full. Do not treat a Tier 1 label as final.

Execute the Tier 1 steps in order. Within a step, batch independent tool calls in parallel.

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

**Preferred: run the bundled scanner.** If `scripts/scan.sh` ships with this skill, run it once — it applies every vendor
pattern deterministically and prints grouped `file:line:match` hits, so Tier 1 becomes a rendering of reproducible output
instead of freehand grepping:

```bash
bash <ABSOLUTE_PATH_TO_SKILL_DIR>/scripts/scan.sh <repo-root>   # repo-root defaults to "."
```

**Fallback: freehand ripgrep.** If the script is absent, run the patterns from `references/dependency-patterns.md` in
parallel via Bash or the Grep tool. They are case-insensitive (`-i`) with word boundaries; ripgrep respects `.gitignore`,
so add `--glob` only for committed `vendor/` dirs, lock files, and `*.md` docs. Examples:

- Firebase: `rg -in "from ['\"]firebase|firebase-admin|firestore\\(|getFirestore"`
- Stripe: `rg -in "from ['\"]stripe['\"]|import Stripe|\\bstripe\\.[a-zA-Z]"`
- MongoDB: `rg -in "\bMongoClient\b|\bmongoose\b|\bpymongo\b|com\\.mongodb"`
- AWS non-S3: `rg -in "aws-sdk|\bboto3\b|@aws-sdk"` (then filter S3-only files out in Step 6)
- OpenAI: `rg -in "from ['\"]?openai\b|\bimport openai\b|\bOpenAI\("` (then check for a `base_url` override in Step 6)

Record every hit as `path:line` with the surrounding context, then group hits by file.

### Step 4 — Assign a tentative role (name/path heuristics only)

For each file with at least one hit, use the **Heuristic** column below to guess a role. In Tier 1 this is a *tentative*
label only: apply the name/path signal and stop. Do NOT read call sites, follow imports, or perform the sole-referencer
check yet — that cross-file work is Tier 2's job. When the heuristics are ambiguous, default to the more severe role
(Violation) and let Tier 2 downgrade it.

| Role | Heuristic | Treat as |
|---|---|---|
| Adapter / Provider / Repository / Gateway | File implements an interface or abstract class AND its name or directory marks it as the vendor's wrapper (e.g. `stripe-payment.adapter.ts`, `adapters/`, `infrastructure/`, `repositories/`). | Acceptable |
| Composition root / Bootstrap | Wires services into a DI container or factory at startup (e.g. `container.ts`, `main.py`, `bootstrap.js`, `wire.go`). | Acceptable |
| Configuration | Reads vendor config from env vars; does not invoke the SDK. | Acceptable |
| Domain or business logic with vendor call | Lives under `domain/`, `core/`, `services/`, `usecases/`, `controllers/`, `handlers/`, `app/`, etc. and imports the SDK directly. | Violation |
| Test using real SDK | Integration test against live vendor. | Low — flag |
| Test mocking the SDK directly | Unit test mocks the vendor instead of an interface. | Medium — coupling leaks into tests |

**Adapter test (Tier 2 — do not perform in Tier 1).** A file is a *real* adapter only if both conditions hold: (a) it
implements an interface or abstract class for that capability, and (b) it is the *only* place that vendor SDK is
referenced for that capability. A file named `*-adapter.*` that still has callers importing the SDK elsewhere is not a
real adapter. Confirming (b) requires a repo-wide grep for the SDK import — the cross-file check the verifier performs.
In Tier 1, a path/name that looks like an adapter earns a *tentative* Acceptable label only.

### Step 5 — Assign tentative severity

Pick the severity that matches the tentative role from Step 4. In Tier 1, mark it as a guess by appending a `?` in the
finding heading (e.g. `[High?]`); Tier 2 removes the `?` when it confirms, or changes the level when it adjusts. The
levels:

- **Critical**: vendor SDK called from the domain layer with no interface anywhere; multiple call sites.
- **High**: vendor SDK called from a service layer that lacks an interface; concentrated in one or two files.
- **Medium**: an interface exists but leaks vendor types through its public surface (e.g. method returns `Stripe.PaymentIntent`), or unit tests mock the SDK directly.
- **Low**: scripts, CLIs, migrations, or integration tests that import the SDK directly while production code is properly abstracted.

### Step 6 — Recognize acceptable patterns

Do not flag any of the following:

- **AWS S3** specifically — open S3 protocol, swappable with MinIO, Ceph, Garage. Other AWS services remain in scope.
- **Standard protocols**: HTTP, HTTPS, SMTP, IMAP, OAuth, OIDC, gRPC, WebSockets, MQTT.
- **OSI-approved open-source datastores**: PostgreSQL, MySQL, MariaDB, SQLite, Cassandra, Redis, Valkey. (Redis 8+
  returned to AGPLv3 in 2025, which is OSI-approved; the 2024 SSPL-only versions are the exception. Valkey, the
  BSD-licensed fork, is always fine.)
- **A vendor SDK imported only inside its dedicated adapter file** (see Step 4).
- **Type-only imports** (`import type ...`) of vendor types when domain types are used everywhere else. If a vendor type
  leaks through a public interface, downgrade to Medium rather than ignore.
- **LLM SDK pointed at a self-hostable, OpenAI-compatible endpoint** — an `openai`/LLM client configured with a
  `base_url`/`baseURL` (or Python `base_url`) that targets a self-hostable, open-weight runtime (vLLM, Ollama, LiteLLM,
  LocalAI, TGI) is like AWS S3 with an `endpoint_url`: the same code runs against a swappable open backend, so lock-in is
  reduced. This exception applies *only* when the endpoint is self-hostable/open. It does **not** apply when:
  - there is no `base_url` override (the SDK hits the vendor's default hosted API — a finding);
  - the `base_url` points at another proprietary SaaS (Azure OpenAI, Groq, Together, Perplexity) — still a finding, and
    re-attribute it to that vendor;
  - the call uses a cloud-proprietary path such as `AnthropicBedrock` / `AnthropicVertex` — still a finding.

When in doubt, flag and let the user decide; document the ambiguity in the finding.

### Step 7 — Write the draft report

Write `PLATFORM-DEPENDENCY-ANALYSIS.md` at the project root using the template below. This is the Tier 1 *draft*; Tier 2
edits it in place, so its structure must be stable:

- Set the header `Verification:` line to `pending`.
- Give each finding (one per grouped file) a **stable claim ID** `PDA-001`, `PDA-002`, ... in discovery order, and a
  `Status: UNVERIFIED` line. Keep the `### [PDA-NNN] [Severity?] ...` heading and the `Status:` line on their own lines,
  format-stable, so the verifier can rewrite them with exact-string edits.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- **Do NOT write the executive-summary severity table yet.** Leave the placeholder note in the template. The table is
  computed LAST — after Tier 2 verification — because verdicts change the counts. Until Tier 2 runs, the draft's severities
  are tentative (`?`) and the summary stays a placeholder.

## Report Template

```markdown
# Platform Dependency Analysis

- Repository: <name>
- Analyzed at: <YYYY-MM-DD>
- Files scanned: <count>
- Languages: <list>
- Verification: pending    <!-- Tier 2 flips this to: completed <YYYY-MM-DD> -->

## Executive Summary

<Two to four sentences: how independent is this codebase, the top concerns, and the recommended next step.
Written LAST, after Tier 2 verification.>

<!-- SEVERITY TABLE: do not fill in during Tier 1. Computed after verification from the final verdicts.
     Replace the placeholder line below with this table (count only findings whose final heading is
     [Critical]/[High]/[Medium]/[Low]; exclude [OK] adapters and [N/A] rejected findings):
     | Severity | Count |
     |---|---|
     | Critical | N |
     | High | N |
     | Medium | N |
     | Low | N |
-->
_Severity table pending verification._

## Findings

### [PDA-001] [Critical?] <Vendor> directly used in domain layer
Status: UNVERIFIED
Claimed role: domain logic with vendor call

Locations:
- `src/services/order.ts:42` direct `stripe.paymentIntents.create(...)` call
- `src/services/order.ts:88` direct `stripe.refunds.create(...)` call

Problem: <one sentence>.

Recommended fix: introduce a `PaymentService` interface (see `references/abstraction-examples.md`), move every Stripe call into a `StripePaymentService` implementation, inject the interface into `OrderService`.

Effort: S / M / L

---

### [PDA-002] [High?] <next finding>
Status: UNVERIFIED
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

## Tier 2 — Verify

The Tier 1 draft is a set of *unverified guesses* from grep context. Tier 2 confirms, adjusts, or rejects each claim with
the call-site and cross-file analysis Tier 1 deliberately skipped. Run it before showing the report to the user.

Spawn **one** general-purpose subagent via the Agent tool. Key mechanics to respect:

- The subagent does **not** inherit this skill — it sees only the prompt you give it. The prompt must therefore point it
  at this `SKILL.md` (the classification rulebook, Steps 4-6) and `references/dependency-patterns.md`, using their
  absolute paths on this machine. Fill in the two `<...>` placeholders before spawning.
- The subagent edits the draft in place with exact-string edits, so it depends on the format-stable heading, `Status:`,
  and `Claimed role:` lines Tier 1 produced. It must not touch the `Verification:` header line or the summary placeholder
  — those are yours to finalize.
- The Agent tool's final report is **not shown to the user**; you relay the outcome yourself (see Finalize).

Use this spawn prompt (verbatim, with placeholders filled):

```text
You are verifying a platform-dependency audit. A draft report already exists; your job is to
confirm, adjust, or reject each finding using call-site and cross-file analysis, and edit the
draft in place. You are NOT re-scanning the repo for new findings.

First, read these files to load the classification rules (do not skip):
- <ABSOLUTE_PATH_TO_SKILL_DIR>/SKILL.md  — Steps 4, 5, 6 are the authoritative rulebook.
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/dependency-patterns.md
Then read the draft report: <ABSOLUTE_PATH_TO_DRAFT>

For EACH finding (each `### [PDA-NNN] ...` block), run this procedure:
  1. Open the flagged file at each cited `path:line`. Confirm the vendor SDK call actually
     exists there. If the cited lines are a comment, a string, a doc, or otherwise not a real
     SDK call, the claim is a false positive -> REJECTED.
  2. Adapter test (the check Tier 1 could not do): does the file (a) implement an interface or
     abstract class for that capability, AND (b) is it the ONLY place that vendor SDK is
     referenced for that capability? Run a repo-wide grep for the SDK import to settle (b). A
     file that looks like an adapter but whose SDK is imported by other files too is NOT a real
     adapter -> it is a violation.
  3. Caller analysis: grep for importers of the flagged module. Check whether vendor types leak
     upward through its public surface (return types, params). A leak downgrades an otherwise-
     clean abstraction to Medium.
  4. LLM-SDK endpoint check (only for OpenAI/Anthropic/Gemini/Cohere/Mistral findings): look for a
     `base_url`/`baseURL` (or Python `base_url`) override where the client is constructed. Per
     Step 6: if it targets a self-hostable, open-weight OpenAI-compatible runtime (vLLM, Ollama,
     LiteLLM, LocalAI, TGI), lock-in is reduced -> REJECT/ADJUST like AWS S3. If there is no
     override, or it points at another proprietary SaaS (Azure OpenAI, Groq, Together, Perplexity)
     or uses Bedrock/Vertex, it stays a finding (re-attribute to the actual vendor if different).
  5. Decide the verdict and severity per Steps 4-6, then edit the draft finding in place:
     - Rewrite the `Status:` line to exactly one of:
         Status: CONFIRMED
         Status: ADJUSTED (<short reason>)
         Status: REJECTED (<short reason>)
     - In the heading `### [PDA-NNN] [Severity?] <title>`, remove the `?`. If you changed the
       level, replace it (e.g. `[High?]` -> `[Medium]`). For REJECTED, use `[N/A]`.
     - Fix `Claimed role:` if the role was wrong.
     - Add one line `Verification note: <what you found, citing path:line>`.

Rules of engagement:
- Edit ONLY the finding blocks. Do NOT edit the `- Verification:` header line, the Executive
  Summary, the severity-table placeholder, or the File Index — the main agent finalizes those.
- Use exact-string edits; preserve every claim ID and the heading/`Status:` line structure.
- When genuinely uncertain after analysis, keep the finding (CONFIRMED or ADJUSTED) and say so
  in the Verification note; do not reject on doubt.

When done, return a plain-text list: one line per claim as `PDA-NNN: <VERDICT> — <one-clause reason>`.
```

**Default: a single verifier.** One subagent edits the whole draft sequentially, so there are no concurrent-edit
conflicts.

**Escalation (not the default): per-vendor fan-out.** For very large repos, spawn one verifier per vendor. To avoid
concurrent edits to one file, fan-out verifiers must **return their verdicts as text only** (the `PDA-NNN: VERDICT —
reason` list) and NOT edit the draft; the main agent then applies every edit itself. (A skill-driven Workflow-tool
fan-out is an acceptable opt-in alternative for this case.)

## Finalize the report (main agent, after Tier 2)

The subagent's report is not shown to the user, and the draft still has a placeholder summary. After the verifier
returns, the main agent must:

1. Read the edited draft. If a fan-out was used, apply the returned verdicts to the draft now.
2. Recompute the severity counts by the finding's final severity label: count only findings whose heading carries a
   real severity (`[Critical]`, `[High]`, `[Medium]`, `[Low]`). Exclude `REJECTED` findings (`[N/A]`) and confirmed-
   acceptable ones (`[OK]`, e.g. a real adapter) — a `CONFIRMED` verdict does not by itself mean "counts as a violation".
   Render the real table into the placeholder (`_Severity table pending verification._`).
3. Update the **File Index** so classification and severity match the final verdicts.
4. Write the **Executive Summary** prose now that the numbers are settled.
5. Flip the header line to `- Verification: completed <YYYY-MM-DD>`.
6. Relay a concise summary to the user: counts by severity, how many claims were confirmed / adjusted / rejected, and
   the top one or two concerns — because the subagent's report never reaches them.
7. If available, produce a html version of the report using `marked`, first test if the tool is present

```bash
   command -v marked # if present, execute the conversion
   marked PLATFORM-DEPENDENCY-ANALYSIS.md > PLATFORM-DEPENDENCY-ANALYSIS.html
```

## When to Read the References

- Read `references/dependency-patterns.md` at the start of Step 3 to retrieve the full pattern list and detection keywords for the languages found in Step 1.
- Read `references/abstraction-examples.md` while drafting "Recommended fix" sections in Step 7, so suggested code matches the shape (interface + implementation + DI wiring) appropriate to the target language.

## Output Discipline

- The report is the deliverable. Do not modify code unless the user explicitly asks for remediation in a follow-up.
- A report is final only after Tier 2. Do not present a draft that still carries `Status: UNVERIFIED` findings or a
  `Verification: pending` header as the finished audit; run the verifier and finalize first.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- Keep each code snippet in the report to roughly ten lines.
- If the repo is clean (no violations), still emit the report so the user has documentation of that fact and the acceptable dependencies.
- Plain ASCII only. No emojis. No utf-8 characters.
