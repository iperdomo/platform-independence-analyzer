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
robustness. Direct dependencies on OSI-approved open-source libraries are **acceptable** and must not be flagged, even
when imported straight from domain code with no abstraction layer. Only proprietary, closed-source, or vendor-controlled
SaaS dependencies count as findings — and **the service's license matters, not the client library's** (`mongoose` is MIT,
but MongoDB's server is SSPL, so it is a finding).

The whole audit is the question "if we had to replace vendor X tomorrow, which non-adapter files would change?" — where
"vendor X" is a *proprietary* dependency. Open-source dependencies can always be forked, self-hosted, or replaced without
vendor cooperation, so they do not create lock-in.

Full scope rules, including the unclear-license default and how to treat vendor relicensing, are **R1** in
`references/classification-rules.md`.

## Workflow

This audit runs in **two tiers**:

- **Tier 1 — Scan (draft)**: a cheap, low-judgment mechanical pass (Steps 1-7). It inventories manifests, greps for vendor
  usage, and writes a *draft* `PLATFORM-DEPENDENCY-ANALYSIS.md` where every finding carries a stable claim ID and
  `Status: UNVERIFIED`. Classification and severity are *tentative* here, assigned from name/path heuristics only — no
  call-site reading, no cross-file analysis.
- **Tier 2 — Verify**: a fresh-context subagent confirms, adjusts, or rejects each claim using call-site and cross-file
  analysis, then the main agent finalizes the report (recomputes the severity table, flips the header to
  `Verification: completed`). Tier 2 is defined in its own section below.

`references/classification-rules.md` is the authoritative rulebook for *both* tiers: Tier 1 applies only its name/path
heuristics (R2) to produce tentative labels; Tier 2 applies every rule in full. Do not treat a Tier 1 label as final.
Steps 4-6 below are pointers into it, not a second copy of the rules.

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

Read each manifest file and build the candidate list that drives Step 3. This runs in two parts; the second is not
optional, because the pattern list is a closed allowlist and every list rots.

**Part 1 — known matches.** List every dependency matching a known proprietary service from
`references/dependency-patterns.md`.

**Part 2 — residual judgment pass.** Every remaining manifest dependency — the ones no pattern matched — gets an
explicit proprietary-or-open call. This is judgment, not pattern matching, and it is the only thing standing between the
audit and a silent zero-finding report on a repo built entirely out of unlisted vendors:

- Dismiss obvious OSI-licensed frameworks, utilities, and build tooling in bulk (`react`, `express`, `flask`,
  `lodash`, `pytest`, `vite`, ...). Do not spend a line each on these.
- For anything that names or wraps a *hosted service* — a database, search index, feature flag system, error tracker,
  CMS, data warehouse, queue, vector store, LLM gateway — decide with the rules already in the scope section: **the
  service's license matters, not the client library's**, and when a license is unclear, **treat it as proprietary and
  flag it**. Many such clients are MIT-licensed wrappers around a non-OSI service (Elasticsearch under SSPL/ELv2,
  Sentry under FSL, MongoDB under SSPL).
- `references/dependency-patterns.md` carries a "Commonly missed proprietary dependencies" list. It is a *seed list to
  make this pass cheap, not an allowlist* — a name's absence from it means nothing, so still judge the rest.

Both parts feed Step 3. Also include any candidate not declared in a manifest but visible in source (e.g. a raw HTTP
call to a vendor endpoint).

Carry the residual-pass results forward explicitly: `scripts/scan.sh` has no pattern for them, so **Step 3 must run a
targeted `rg` for each judgment-derived package name** or those dependencies produce no `file:line` evidence and vanish
from the report.

### Step 3 — Locate usage sites

**Preferred: run the bundled scanner.** If `scripts/scan.sh` ships with this skill, run it once — it applies every vendor
pattern deterministically and prints grouped `file:line:match` hits, so Tier 1 becomes a rendering of reproducible output
instead of freehand grepping:

**Redirect the output to a file and Read that file** — do not consume it as Bash stdout. Tool output is capped at tens
of KB, and on a mid-sized repo with a chatty vendor (Datadog, aws-sdk) the hits past that cap vanish silently, leaving a
draft that looks complete and is not. That is the worst failure mode an audit has.

```bash
bash <ABSOLUTE_PATH_TO_SKILL_DIR>/scripts/scan.sh <repo-root> > <SCRATCHPAD>/scan.txt 2>&1; wc -l <SCRATCHPAD>/scan.txt
```

Then Read `<SCRATCHPAD>/scan.txt`, in chunks if it is large. The scanner prints a **HIT SUMMARY** table first: per-vendor
counts, then a total. Check the detail you actually read against those counts — if they disagree, you are missing hits
and must read the rest of the file before drafting.

**`rg` is a hard requirement.** If it is not installed the script exits 127. Stop the audit there and tell the user to
install ripgrep — do not substitute another search path and do not press on with partial results. An audit's value is
its completeness; a scan run through a different engine is not the reproducible scan this skill's findings claim to be,
and a half-scanned repo reported as clean is worse than no report.

**Always: sweep the Step 2 residual candidates too.** The scanner only knows its built-in patterns, so every dependency
flagged by Step 2's judgment pass needs its own grep — the import name, not the package name, when they differ
(`@sentry/node` -> `@sentry/`, `snowflake-connector-python` -> `\bsnowflake\b`). The sweep is `-i`, so do not spell out
case variants:

```bash
rg -in --glob '!**/vendor/**' --glob '!**/*.lock' --glob '!**/*.md' -e "<import-name-1>" -e "<import-name-2>" .
```

A residual candidate with no source hits is a declared-but-unused dependency: note it in the report's Acceptable
Dependencies section rather than raising a finding with no `path:line` evidence.

**Fallback: freehand ripgrep.** If the script is absent, run the mirrored one-liners from the "Ripgrep One-Liners"
section of `references/dependency-patterns.md` via Bash — they are the same patterns the script applies, kept in sync
with it, and they run verbatim. They are case-insensitive (`-i`) with word boundaries; ripgrep respects `.gitignore`, so
add `--glob` only for committed `vendor/` dirs, lock files, `*.md` docs, and the audit's own
`PLATFORM-DEPENDENCY-ANALYSIS.*` output. Do not hand-write patterns from memory here — copying the reference's is what
keeps a script-less run comparable to a scripted one.

Record every hit as `path:line` with the surrounding context, then group hits by file.

Two sweeps overlap the SDK sweeps deliberately, so expect duplicates and de-duplicate when grouping:

- **Raw HTTP endpoints** catch vendor calls made with `fetch`/`httpx`/`curl` and no SDK at all — the case every SDK
  pattern misses. It is the noisiest sweep by design (config files, comments, allowlists); Tier 2 prunes it.
- **LLM wrapper SDKs** catch `langchain_openai`, `@ai-sdk/*`, `llama_index.llms.*`, `litellm` and friends, where the
  vendor SDK is a transitive dependency the direct vendor patterns never see.

A file can therefore appear under several vendor groups (`api.stripe.com` hits both Stripe and the HTTP sweep). It still
produces **one** finding, naming every vendor involved — never one finding per group.

**Language coverage — do not read silence as cleanliness.** The patterns cover **JavaScript/TypeScript, Python, Java,
Go, and .NET/C#**. Step 1 also reads `Gemfile`, `composer.json`, and `Cargo.toml`, but **no pattern covers Ruby, PHP, or
Rust import shapes**. For those ecosystems the scanner returning nothing means nothing was *searched for*, not that
nothing is there — grep explicitly for the vendor names Step 2 inventoried, using the language's own import syntax
(`use Stripe\`, `Stripe::`, `mongodb::`, `aws_sdk_`, ...). `references/dependency-patterns.md` lists the common shapes
per language. This is the same targeted sweep the Step 2 residual candidates need, so run them together.

### Step 4 — Assign a tentative role (name/path heuristics only)

Apply **R2** of `references/classification-rules.md` — the Heuristic column only. In Tier 1 this is a *tentative* label:
apply the name/path signal and stop. Do NOT read call sites, follow imports, or perform the sole-referencer check (R2a)
— that cross-file work is Tier 2's job. When the heuristics are ambiguous, default to the more severe role (Violation)
and let Tier 2 downgrade it.

### Step 5 — Assign tentative severity

Apply **R3** of the rulebook. In Tier 1, mark the level as a guess by appending a `?` in the finding heading (e.g.
`[High?]`); Tier 2 removes the `?` when it confirms, or changes the level when it adjusts.

### Step 6 — Recognize acceptable patterns

Apply **R4** of the rulebook: AWS S3, standard protocols, OSI-approved datastores, vendor SDKs confined to their adapter,
type-only imports, and LLM SDKs pointed at a self-hostable endpoint are not findings. R4 also carries the LLM
wrapper-attribution rule and the four exclusions to the self-hostable-endpoint exception. When in doubt, flag and let the
user decide; document the ambiguity in the finding.

**The rulebook is the authority for Steps 4-6, and it is what the Tier 2 verifier reads.** Read
`references/classification-rules.md` in full before classifying — these three stubs tell you which rule applies, not what
it says.

### Step 7 — Write the draft report

Write `PLATFORM-DEPENDENCY-ANALYSIS.md` at the project root using the template below. This is the Tier 1 *draft*; Tier 2
edits it in place, so its structure must be stable:

- Set the header `Verification:` line to `pending`.
- Give each finding (one per grouped file) a **stable claim ID** `PDA-001`, `PDA-002`, ... in discovery order, and a
  `Status: UNVERIFIED` line. Keep the `### [PDA-NNN] [Severity?] ...` heading and the `Status:` line on their own lines,
  format-stable, so the verifier can rewrite them with exact-string edits.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- For findings that came from Step 2's **residual judgment pass** rather than a known pattern, state the license basis in
  the `Problem:` sentence — which service the dependency binds to and under what license (e.g. "`@sentry/node` is a
  client for Sentry's hosted service, licensed FSL, not OSI-approved"). Tier 2 then checks your reasoning instead of
  re-deriving the license from its own training data, which is frozen and often stale.
- **Do NOT write the executive-summary severity table or the File Index yet.** Leave both placeholder lines in place.
  They are computed LAST — after Tier 2 verification — because verdicts change the counts and the classifications. Until
  Tier 2 runs, the draft's severities are tentative (`?`); anything derived from them would be state that drifts.
- Compute `Files scanned:` with the command in the template rather than estimating it.

## Report Template

```markdown
# Platform Dependency Analysis

- Repository: <name>
- Analyzed at: <YYYY-MM-DD>
- Files scanned: <count>   <!-- compute it, do not estimate: `rg --files | wc -l` (respects .gitignore, works in any directory).
                              `git ls-files | wc -l` also works but counts only TRACKED files - it returns 0 in a repo whose
                              files are all still untracked, which would put a false "0" in the report. -->
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

<!-- FILE INDEX: do not fill in during Tier 1. Written at finalize from the final verdicts, like the
     severity table — a Tier 1 index would carry tentative severities that Tier 2 then changes, and
     duplicated state drifts. Final form:
     | File | Vendor | Classification | Severity |
     |---|---|---|---|
     | src/services/order.ts | Stripe | Domain logic with vendor call | Critical |
     | src/adapters/stripe-payment.adapter.ts | Stripe | Adapter | OK |
-->
_File index pending verification._
```

## Tier 2 — Verify

The Tier 1 draft is a set of *unverified guesses* from grep context. Tier 2 confirms, adjusts, or rejects each claim with
the call-site and cross-file analysis Tier 1 deliberately skipped. Run it before showing the report to the user.

Spawn **one** general-purpose subagent via the Agent tool. Key mechanics to respect:

- The subagent does **not** inherit this skill — it sees only the prompt you give it. The prompt points it at
  `references/classification-rules.md` and `references/dependency-patterns.md` by absolute path, and explicitly tells it
  **not** to read this `SKILL.md`: a fresh context reading the scan workflow, the report template, and its own spawn
  prompt would be following imperatives that contradict its job. Fill in the three `<...>` placeholders before spawning
  (skill dir, repo root, draft path).
- The subagent edits the draft in place with exact-string edits, so it depends on the format-stable heading, `Status:`,
  and `Claimed role:` lines Tier 1 produced. It must not touch the `Verification:` header line or the summary placeholder
  — those are yours to finalize.
- The Agent tool's final report is **not shown to the user**; you relay the outcome yourself (see Finalize).

Use this spawn prompt (verbatim, with placeholders filled):

```text
You are verifying a platform-dependency audit. A draft report already exists; your job is to
confirm, adjust, or reject each finding using call-site and cross-file analysis, and edit the
draft in place. You are NOT re-scanning the repo for new findings.

Repo root: <ABSOLUTE_PATH_TO_REPO_ROOT>   (run every repo-wide grep from here)

First, read these two files — they are the complete rules you need, and the only ones:
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/classification-rules.md  — the authoritative rulebook
  (R1 scope, R2 roles, R2a adapter test, R3 severity, R4 acceptable patterns, R5 env-var
  endpoints, R6 what counts as real usage). Read it in full before judging anything.
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/dependency-patterns.md  — vendor patterns, the dated
  license table, and LLM wrapper attribution.
Then read the draft report: <ABSOLUTE_PATH_TO_DRAFT>

Do NOT read the skill's SKILL.md — it contains the scan workflow and this prompt, none of which
apply to your job.

For EACH finding (each `### [PDA-NNN] ...` block), run this procedure:
  1. Open the flagged file at each cited `path:line` and confirm real vendor usage exists there,
     per R6 — SDK call/import, raw HTTP to a vendor endpoint, or a transitive LLM wrapper import
     all count. Do NOT reject a finding merely because it is not an SDK import. Cited lines that
     are a comment, a doc, or a test fixture string are false positives -> REJECTED.
  2. Adapter test (R2a — the check Tier 1 could not do): does the file (a) implement an interface
     or abstract class for that capability, AND (b) is it the ONLY place that vendor SDK is
     referenced for that capability? Run a repo-wide grep for the SDK import to settle (b). A
     file that looks like an adapter but whose SDK is imported by other files too is NOT a real
     adapter -> it is a violation. Mind R2a's note: a bypass that reaches the same vendor without
     the SDK is its own finding, not a reason to fail an otherwise clean adapter.
  3. Caller analysis: grep for importers of the flagged module. Check whether vendor types leak
     upward through its public surface (return types, params). A leak downgrades an otherwise-
     clean abstraction to Medium (R3).
  4. LLM findings only (OpenAI/Anthropic/Gemini/Cohere/Mistral, including ones reached through a
     wrapper such as langchain_*, @ai-sdk/*, llama_index.llms.*, litellm):

     4a. Wrapper attribution (R4). The wrapper library is MIT/Apache and is never itself the
         finding — re-title the finding after the proprietary model API it binds to. Then judge
         the shape: code written against a provider-agnostic type with the concrete provider
         chosen at composition time, or a litellm call whose model string comes from config, is
         acting AS the abstraction -> ADJUST down (or [OK], like a real adapter). `ChatOpenAI`
         imported straight into a use case, or a hardcoded proprietary model string in domain
         code, stays a finding.

     4b. Endpoint check (R4 + R5). Look for a `base_url`/`baseURL` override where the client is
         constructed. Self-hostable open-weight runtime (vLLM, Ollama, LiteLLM, LocalAI, TGI) ->
         reduced lock-in, REJECT/ADJUST like AWS S3. No override, another proprietary SaaS
         (Azure OpenAI, Groq, Together, Perplexity), or Bedrock/Vertex -> still a finding,
         re-attributed to the actual vendor. If the override reads an env var, walk R5's
         resolution ladder before deciding; if it does not resolve, the verdict is
         `ADJUSTED (endpoint indeterminate)` at Low or Medium with the ambiguity spelled out —
         NOT `REJECTED`.
  5. Decide the verdict and severity per R2-R4, then edit the draft finding in place:
     - Rewrite the `Status:` line to exactly one of:
         Status: CONFIRMED
         Status: ADJUSTED (<short reason>)
         Status: REJECTED (<short reason>)
       Per R4a: REJECTED means the CLAIM was wrong (not real vendor usage -> `[N/A]`). Real usage
       that is simply acceptable — a genuine adapter, S3-only, a resolved self-hosted endpoint —
       is ADJUSTED with `[OK]`, not REJECTED.
     - In the heading `### [PDA-NNN] [Severity?] <title>`, remove the `?`. If you changed the
       level, replace it (e.g. `[High?]` -> `[Medium]`). For REJECTED, use `[N/A]`.
     - Fix `Claimed role:` if the role was wrong.
     - Add one line `Verification note: <what you found, citing path:line>`.

Rules of engagement:
- Edit ONLY the finding blocks. Do NOT edit the `- Verification:` header line, the Executive
  Summary, the severity-table placeholder, or the File Index — the main agent finalizes those.
- Use exact-string edits. Every finding carries an identical `Status: UNVERIFIED` line, so that
  line alone is NOT a unique anchor and the Edit tool will reject it. Always include the
  `### [PDA-NNN] ...` heading line in the `old_string` when rewriting a `Status:` line, and
  rewrite the heading and the status together in one edit. Never use replace_all — it would
  corrupt every other finding.
- Preserve every claim ID and the heading/`Status:` line structure.
- When genuinely uncertain after analysis, keep the finding (CONFIRMED or ADJUSTED) and say so
  in the Verification note; do not reject on doubt.
- Some findings cite a license basis in their `Problem:` line (e.g. "Sentry's server is FSL, not
  OSI-approved"). Do NOT overturn those from memory — your training data on vendor relicensing is
  frozen and frequently stale. The dated license table in dependency-patterns.md is the
  authority; if a claim contradicts it, adjust, and if neither settles it, keep the finding with
  an ambiguity note.

When done, return a plain-text list: one line per claim as `PDA-NNN: <VERDICT> — <one-clause reason>`.
```

**Default: a single verifier.** One subagent edits the whole draft sequentially, so there are no concurrent-edit
conflicts.

**Escalation (not the default): per-vendor fan-out.** Use it when the draft has **more than 20 findings or more than 8
distinct vendors** — past roughly that point a single verifier doing per-claim reads plus repo-wide greps starts running
out of context, and quality degrades silently. Below the threshold, one verifier; at or above it, spawn one per vendor. To avoid
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
3. Render the **File Index** into its placeholder (`_File index pending verification._`) from the final verdicts — one
   row per file, including `[OK]` adapters and `[N/A]` rejections so the reader sees what was checked and cleared.
4. Write the **Executive Summary** prose now that the numbers are settled.
   Then sweep the findings for leftover Tier 1 placeholder text: the verifier is told to edit only status, heading,
   role, and its verification note, so a `Recommended fix: pending verification.` line in a claim it just CONFIRMED is
   yours to replace with the real recommendation.
5. Flip the header line to `- Verification: completed <YYYY-MM-DD>`.
6. Relay a concise summary to the user: counts by severity, how many claims were confirmed / adjusted / rejected, and
   the top one or two concerns — because the subagent's report never reaches them.
7. If available, produce a html version of the report using `marked`, first test if the tool is present

```bash
   command -v marked # if present, execute the conversion
   marked PLATFORM-DEPENDENCY-ANALYSIS.md > PLATFORM-DEPENDENCY-ANALYSIS.html
```

## When to Read the References

- Read `references/classification-rules.md` before Step 4 — it is the authority for roles, severity, and acceptable
  patterns, and it is the only rules file the Tier 2 verifier is given.
- Read `references/dependency-patterns.md` at the start of **Step 2** — both for the known-service list that drives Part 1 and for the "Commonly missed proprietary dependencies" table that makes Part 2's judgment pass cheap. It also carries the full pattern list and detection keywords used in Step 3.
- Read `references/abstraction-examples.md` while drafting "Recommended fix" sections in Step 7, so suggested code matches the shape (interface + implementation + DI wiring) appropriate to the target language.

## Output Discipline

- The report is the deliverable. Do not modify code unless the user explicitly asks for remediation in a follow-up.
- A report is final only after Tier 2. Do not present a draft that still carries `Status: UNVERIFIED` findings or a
  `Verification: pending` header as the finished audit; run the verifier and finalize first.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- Keep each code snippet in the report to roughly ten lines.
- If the repo is clean (no violations), still emit the report so the user has documentation of that fact and the acceptable dependencies.
- Plain ASCII only. No emojis. No utf-8 characters.
