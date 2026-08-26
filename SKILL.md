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

```bash
bash <ABSOLUTE_PATH_TO_SKILL_DIR>/scripts/scan.sh <repo-root>   # repo-root defaults to "."
```

**Always: sweep the Step 2 residual candidates too.** The scanner only knows its built-in patterns, so every dependency
flagged by Step 2's judgment pass needs its own grep — the import name, not the package name, when they differ
(`@sentry/node` -> `@sentry/`, `snowflake-connector-python` -> `\bsnowflake\b`). The sweep is `-i`, so do not spell out
case variants:

```bash
rg -in --glob '!**/vendor/**' --glob '!**/*.lock' --glob '!**/*.md' -e "<import-name-1>" -e "<import-name-2>" .
```

A residual candidate with no source hits is a declared-but-unused dependency: note it in the report's Acceptable
Dependencies section rather than raising a finding with no `path:line` evidence.

**Fallback: freehand ripgrep.** If the script is absent, run the patterns from `references/dependency-patterns.md` in
parallel via Bash or the Grep tool. They are case-insensitive (`-i`) with word boundaries; ripgrep respects `.gitignore`,
so add `--glob` only for committed `vendor/` dirs, lock files, and `*.md` docs. Examples:

- Firebase: `rg -in "from ['\"]firebase|firebase-admin|firestore\\(|getFirestore"`
- Stripe: `rg -in "from ['\"]stripe['\"]|import Stripe|\\bstripe\\.[a-zA-Z]"`
- MongoDB: `rg -in "\bMongoClient\b|\bmongoose\b|\bpymongo\b|com\\.mongodb"`
- AWS non-S3: `rg -in "aws-sdk|\bboto3\b|@aws-sdk"` (then filter S3-only files out in Step 6)
- OpenAI: `rg -in "from ['\"]?openai\b|\bimport openai\b|\bOpenAI\("` (then check for a `base_url` override in Step 6)

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

**Ambiguity discount.** When a coupling is real but its *magnitude* depends on deployment config the repo does not
settle — the indeterminate LLM `base_url` of Step 6 being the standard case — cap the severity at **Medium**, or **Low**
when production code is otherwise abstracted, and state the unresolved question in the finding. Unresolved ambiguity
lowers the level; it never removes the finding.

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
  - the call uses a cloud-proprietary path such as `AnthropicBedrock` / `AnthropicVertex` — still a finding;
  - **the endpoint is indeterminate** — a bare `os.environ["LLM_BASE_URL"]` with no default could be vLLM, Groq, or
    the vendor's own API depending on deployment. Try to resolve it (Tier 2 step 4b lists where to look); if it stays
    unknowable, keep the finding at **Low or Medium with an ambiguity note**. Never reject on an unresolvable variable
    — the exception rewards a codebase that *shows* its endpoint is open, not one that hides it behind a variable.

**LLM wrapper libraries (LangChain, LlamaIndex, Vercel AI SDK, LiteLLM).** These are MIT/Apache-licensed, so the wrapper
itself is never the finding — attribute it to the proprietary model API it binds to (`from langchain_openai import
ChatOpenAI` is an *OpenAI* finding). But a provider-agnostic wrapper can itself *be* the abstraction: code written
against a generic chat-model type with the concrete provider chosen at composition time, or a LiteLLM call whose model
string comes from config, is doing an adapter's job and lock-in is reduced. Code importing `ChatOpenAI` straight into a
use case, or hardcoding a proprietary model string in domain code, is not. Tier 1 surfaces the import; Tier 2 decides
which shape it is. See "LLM Wrapper Attribution" in `references/dependency-patterns.md`.

When in doubt, flag and let the user decide; document the ambiguity in the finding.

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
  1. Open the flagged file at each cited `path:line`. Confirm real vendor usage exists there.
     Three shapes all count as real usage, do NOT reject a finding merely because it is not the
     first one:
       (a) a vendor SDK call or import;
       (b) a request to a vendor HTTP endpoint with no SDK involved (`fetch`/`httpx`/`axios`/
           `requests` against api.stripe.com, api.openai.com, *.googleapis.com, ...) — a URL in
           a config constant or env default that is then used to build requests counts;
       (c) an LLM wrapper import (`langchain_openai`, `@ai-sdk/*`, `llama_index.llms.*`,
           `litellm`) that reaches a proprietary model API transitively.
     If the cited lines are a comment, a doc, a test fixture string, or otherwise not real
     usage, the claim is a false positive -> REJECTED.
  2. Adapter test (the check Tier 1 could not do): does the file (a) implement an interface or
     abstract class for that capability, AND (b) is it the ONLY place that vendor SDK is
     referenced for that capability? Run a repo-wide grep for the SDK import to settle (b). A
     file that looks like an adapter but whose SDK is imported by other files too is NOT a real
     adapter -> it is a violation.
  3. Caller analysis: grep for importers of the flagged module. Check whether vendor types leak
     upward through its public surface (return types, params). A leak downgrades an otherwise-
     clean abstraction to Medium.
  4. LLM findings only (OpenAI/Anthropic/Gemini/Cohere/Mistral, including ones reached through a
     wrapper such as langchain_*, @ai-sdk/*, llama_index.llms.*, litellm):

     4a. Wrapper attribution. The wrapper library is MIT/Apache and is never itself the finding —
         re-title the finding after the proprietary model API it binds to. Then judge the shape:
         code written against a provider-agnostic type with the concrete provider chosen at
         composition time, or a litellm call whose model string comes from config, is acting AS
         the abstraction -> ADJUST down (or [OK], like a real adapter). `ChatOpenAI` imported
         straight into a use case, or a hardcoded proprietary model string in domain code, stays
         a finding.

     4b. Endpoint check. Look for a `base_url`/`baseURL` (or Python `base_url`) override where the
         client is constructed. Per Step 6: if it targets a self-hostable, open-weight
         OpenAI-compatible runtime (vLLM, Ollama, LiteLLM, LocalAI, TGI), lock-in is reduced ->
         REJECT/ADJUST like AWS S3. If there is no override, or it points at another proprietary
         SaaS (Azure OpenAI, Groq, Together, Perplexity) or uses Bedrock/Vertex, it stays a
         finding (re-attribute to the actual vendor if different).

         When the override reads from an env var, the endpoint is NOT knowable from that line —
         you must chase the actual value before deciding. Look, stopping at the first hit:
           (i)   a literal default in the call itself (`os.environ.get(..., "http://...")`,
                 `process.env.X ?? "http://..."`);
           (ii)  `.env.example`, `.env.sample`, `.env.defaults`, `.env.template` — a variable
                 listed there with an EMPTY value resolves nothing, keep looking;
           (iii) `docker-compose*.yml` (an ollama/vllm/litellm service next to the app is strong
                 evidence), Helm `values.yaml`, k8s manifests, Terraform;
           (iv)  config modules with a fallback constant, CI workflow env blocks, README or
                 deployment docs.
         If the value resolves, judge it as above. If it does NOT resolve, the verdict is
         `ADJUSTED (endpoint indeterminate)` at Low or Medium with the ambiguity spelled out in
         the Verification note — NOT `REJECTED`. An unresolvable variable is missing evidence,
         not evidence of an open endpoint.
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
- Some findings cite a license basis in their `Problem:` line (e.g. "Sentry's server is FSL, not
  OSI-approved"). Do NOT overturn those from memory — your training data on vendor relicensing is
  frozen and frequently stale. The license table in dependency-patterns.md is the authority; if a
  claim contradicts it, adjust, and if neither settles it, keep the finding with an ambiguity note.

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
