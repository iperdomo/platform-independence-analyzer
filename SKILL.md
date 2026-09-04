---
name: platform-independence-analyzer
description: Audit a code repository for direct dependencies on closed-source or proprietary services (Firebase, Google Maps, Stripe, Twilio, SendGrid, MongoDB, LLM/AI APIs like OpenAI, Anthropic, Gemini, Cohere, Mistral, vendor SDKs, cloud-specific functions, etc.) that lack an abstraction layer. Use when the user asks to evaluate platform independence, vendor lock-in, proprietary-dependency coupling, swappability of services, missing adapter/repository/port layers, or to produce a PLATFORM-DEPENDENCY-ANALYSIS.md report. Covers React Native / mobile repos, where proprietary services are reached through binding modules (@react-native-firebase, react-native-purchases, react-native-onesignal) and declared again in Podfile/build.gradle. Triggers on phrases such as "platform independence", "vendor lock-in", "proprietary dependency audit", "check for closed-source dependencies", "are we coupled to <vendor>", "can we swap <vendor>", "are we locked into OpenAI", "are we locked into Firebase", "LLM/AI vendor lock-in", "mobile vendor lock-in".
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
SaaS dependencies count as findings - and **the service's license matters, not the client library's** (`mongoose` is MIT,
but MongoDB's server is SSPL, so it is a finding).

The whole audit is the question "if we had to replace vendor X tomorrow, which non-adapter files would change?" - where
"vendor X" is a *proprietary* dependency. Open-source dependencies can always be forked, self-hosted, or replaced without
vendor cooperation, so they do not create lock-in.

Full scope rules, including the unclear-license default and how to treat vendor relicensing, are **R1** in
`references/classification-rules.md`.

## Workflow

This audit runs in **two tiers**:

- **Tier 1 - Scan (draft)**: a cheap, low-judgment mechanical pass (Steps 1-7). It inventories manifests, greps for vendor
  usage, and writes a *draft* `PLATFORM-DEPENDENCY-ANALYSIS.md` where every finding carries a stable claim ID and
  `Status: UNVERIFIED`. Classification and severity are *tentative* here, assigned from name/path heuristics only - no
  call-site reading, no cross-file analysis.
- **Tier 2 - Verify**: a fresh-context subagent confirms, adjusts, or rejects each claim using call-site and cross-file
  analysis, then the main agent finalizes the report (recomputes the severity table, flips the header to
  `Verification: completed`). Tier 2 is defined in its own section below.

`references/classification-rules.md` is the authoritative rulebook for *both* tiers: Tier 1 applies only its name/path
heuristics (R2) to produce tentative labels; Tier 2 applies every rule in full. Do not treat a Tier 1 label as final.
Steps 4-6 below are pointers into it, not a second copy of the rules.

Execute the Tier 1 steps in order. Within a step, batch independent tool calls in parallel.

### Step 1 - Establish scope

**This skill audits ONE repository per run.** A directory containing several independent repositories is audited by
running the skill once inside each of them and consolidating afterwards (see "Consolidating a multi-repository audit").

**Preferred: run the bundled discovery script.** It answers the repo-shape question and finds the manifests
recursively, which is the part a freehand pass reliably gets wrong:

```bash
bash <ABSOLUTE_PATH_TO_SKILL_DIR>/scripts/manifests.sh <repo-root> > <SCRATCHPAD>/manifests.txt 2>&1; echo "exit=$?"
```

Read `<SCRATCHPAD>/manifests.txt`. Exit code 2 means "several nested repositories" - see 1a. The script needs `rg`
(exit 127 without it) and is the same hard requirement as Step 3.

**1a. Repository shape - a guard, not a formality.** If the working directory has no root `.git` and two or more child
directories each carry their own `.git`, **STOP the audit**: list the repositories found and tell the user to invoke
the skill inside each one. Do not scan anyway. Merging unrelated projects produces meaningless severity counts and a
File Index that mixes codebases - a wrong report, not a rough one.

**1b. Manifests, recursively.** Manifests almost never live only at the root; in the corpus this skill was calibrated
against, 296 of 316 sat at depth 2-4. Read every manifest the script lists, not just the shallow ones, and treat a thin
or empty root manifest as a warning rather than an answer (`pyproject.toml` holding only lint config, a
CI-tooling-only `Package.swift`, a stray `package.json` in a Flutter repo). The full format list, the decoy shapes,
non-manifest declaration sources (`.env.example`, framework config, lock files, git-URL and extras-encoded deps), and
the import-derived fallback for repositories with no manifest at all are in `references/manifest-discovery.md` - read
it now if the script reports anything other than a single conventional manifest set.

**1c. Structure and coverage.** Record: the languages present; the architectural style if visible from the layout
(layered, hexagonal/ports-and-adapters, clean, MVC), since it determines what "domain" means in Step 4; the
sub-projects (workspace packages, `packages/*`, `backend/` + `frontend/`), because findings and the File Index are
grouped by sub-project in Step 7; and any **coverage limit** - uninitialized submodules, a `.sln` enumerating projects
that do not exist on disk, an ecosystem with no pattern coverage. Coverage limits go in the report header.

**1d. Deployment and runtime config** (`docker-compose*.yml`, Helm values, `serverless.yml`, `Procfile`, CI workflows,
`app.config.js`, `eas.json`) is **out of scope as a finding source** (R1) but is read as *evidence*: resolving an
env-var endpoint (R5), confirming which vendor products are enabled, and catching dynamic Expo config that overrides
`app.json`. A repo whose only vendor coupling is in deployment files reports no code-level findings - say so
explicitly, so the clean result reads as deliberate.

- Always exclude these paths from searches: `node_modules`, `vendor`, `dist`, `build`, `target`, `.git`, `.venv`,
  `__pycache__`, `coverage`, `.next`, `.cache`, `Pods`, `.expo`, `ios/build`, generated code directories, and lock
  files. `*.pbxproj` is excluded from *usage* scanning (it is generated and restates the Podfile) but is still read in
  Step 1 as a declaration source for SwiftPM packages.

### Step 2 - Inventory declared proprietary dependencies

Read **every** manifest Step 1 found - all depths, all sub-projects - and build the candidate list that drives Step 3.
Tag each candidate with the sub-project it came from; that tag carries through to the findings and the File Index.

This runs in two parts; the second is not optional, because the pattern list is a closed allowlist and every list rots.

**Part 1 - known matches.** List every dependency matching a known proprietary service from
`references/dependency-patterns.md`.

**Part 2 - residual judgment pass.** Every remaining manifest dependency - the ones no pattern matched - gets an
explicit proprietary-or-open call. This is judgment, not pattern matching, and it is the only thing standing between the
audit and a silent zero-finding report on a repo built entirely out of unlisted vendors:

- Dismiss obvious OSI-licensed frameworks, utilities, and build tooling in bulk (`react`, `express`, `flask`,
  `lodash`, `pytest`, `vite`, ...). Do not spend a line each on these.
- For anything that names or wraps a *hosted service* - a database, search index, feature flag system, error tracker,
  CMS, data warehouse, queue, vector store, LLM gateway - decide with the rules already in the scope section: **the
  service's license matters, not the client library's**, and when a license is unclear, **treat it as proprietary and
  flag it**. Many such clients are MIT-licensed wrappers around a non-OSI service (Elasticsearch under SSPL/ELv2,
  Sentry under FSL, MongoDB under SSPL).
- `references/dependency-patterns.md` carries a "Commonly missed proprietary dependencies" list. It is a *seed list to
  make this pass cheap, not an allowlist* - a name's absence from it means nothing, so still judge the rest.

**Part 3 - sources that are not manifests.** A dependency surface is not only what the manifests declare. Add
candidates from: `.env.example` and friends (vendor hosts, gateway URLs, API keys), framework config files (Laravel
`config/services.php` / `config/mail.php`, a PHP config hardcoding a third-party gateway), lock files (the only place a
*transitive* vendor SDK appears), git-URL dependencies (`pkg @ git+https://...`, invisible to name matching),
extras-encoded dependencies (`django-storages[azure,boto3]`, an optional-extras block), mobile service config
(`google-services.json`, `GoogleService-Info.plist`), and anything visible in source but declared nowhere - a raw HTTP
call to a vendor endpoint. `references/manifest-discovery.md` D7 has the full list.

**Manifest-less repositories.** When Step 1 found no manifest at all, do NOT report the repo as dependency-free.
Derive the candidate list from import statements instead (D8 has the sweeps), judge those names by the same rules, and
state in the report that the dependency inventory came from imports rather than declarations.

All three parts feed Step 3.

Carry the residual-pass results forward explicitly: `scripts/scan.sh` has no pattern for them, so **Step 3 must run a
targeted `rg` for each judgment-derived package name** or those dependencies produce no `file:line` evidence and vanish
from the report.

### Step 3 - Locate usage sites

**Preferred: run the bundled scanner.** If `scripts/scan.sh` ships with this skill, run it once - it applies every vendor
pattern in `references/patterns.tsv` (the one pattern table; the script reads it at runtime) and prints grouped
`file:line:match` hits, so Tier 1 becomes a rendering of reproducible output instead of freehand grepping:

**Redirect the output to a file and Read that file** - do not consume it as Bash stdout. Tool output is capped at tens
of KB, and on a mid-sized repo with a chatty vendor (Datadog, aws-sdk) the hits past that cap vanish silently, leaving a
draft that looks complete and is not. That is the worst failure mode an audit has.

```bash
bash <ABSOLUTE_PATH_TO_SKILL_DIR>/scripts/scan.sh <repo-root> > <SCRATCHPAD>/scan.txt 2>&1; wc -l <SCRATCHPAD>/scan.txt
```

Then Read `<SCRATCHPAD>/scan.txt`, in chunks if it is large. The scanner prints a **HIT SUMMARY** (exact per-vendor
counts) and a **HITS BY DIRECTORY** table before any detail. Those counts are always complete.

The printed *detail* is not always complete, and the difference matters:

- A group whose hits exceed the detail cap ends with an explicit `# SAMPLED: showing N of M hits (up to K per
  directory)` line. That is a deliberate, coverage-preserving sample - every directory with hits is represented, so a
  vendored SDK tree cannot crowd out first-party call sites. Work from the sample, and when a sampled group matters to
  a finding, re-run a directory-scoped `rg` for that vendor to get its full site list.
- A detail block that falls short of its count with **no** `# SAMPLED` line means the output was truncated downstream -
  that is the failure mode to catch. Read the rest of the file before drafting.

**`rg` is a hard requirement.** If it is not installed the script exits 127. Stop the audit there and tell the user to
install ripgrep - do not substitute another search path and do not press on with partial results. An audit's value is
its completeness; a scan run through a different engine is not the reproducible scan this skill's findings claim to be,
and a half-scanned repo reported as clean is worse than no report.

**Always: sweep the Step 2 residual candidates too.** The scanner only knows its built-in patterns, so every dependency
flagged by Step 2's judgment pass needs its own grep - the import name, not the package name, when they differ
(`@sentry/node` -> `@sentry/`, `snowflake-connector-python` -> `\bsnowflake\b`). The sweep is `-i`, so do not spell out
case variants:

```bash
rg -in --glob '!**/vendor/**' --glob '!**/*.lock' --glob '!**/*.md' -e "<import-name-1>" -e "<import-name-2>" .
```

A residual candidate with no source hits is a declared-but-unused dependency: note it in the report's Acceptable
Dependencies section rather than raising a finding with no `path:line` evidence.

**Fallback: freehand ripgrep.** If the script cannot run, generate the one-liners rather than retyping patterns from
memory - `bash <SKILL_DIR>/scripts/scan.sh --print-patterns` prints one ready-to-paste `rg -in '<pattern>'` per vendor
group, with its judgment note. They are the same patterns the scan applies, because both come from the one pattern
table, `references/patterns.tsv`. They are case-insensitive (`-i`) with word boundaries; ripgrep respects `.gitignore`,
so add `--glob` only for committed `vendor/` dirs, lock files, `*.md` docs, and the audit's own
`PLATFORM-DEPENDENCY-ANALYSIS.*` output. Hand-written patterns are what makes a script-less run incomparable to a
scripted one - do not write them.

Record every hit as `path:line` with the surrounding context, then group hits by file.

Two sweeps overlap the SDK sweeps deliberately, so expect duplicates and de-duplicate when grouping:

- **Raw HTTP endpoints** catch vendor calls made with `fetch`/`httpx`/`curl` and no SDK at all - the case every SDK
  pattern misses. It is the noisiest sweep by design (config files, comments, allowlists); Tier 2 prunes it.
- **LLM wrapper SDKs** catch `langchain_openai`, `@ai-sdk/*`, `llama_index.llms.*`, `litellm` and friends, where the
  vendor SDK is a transitive dependency the direct vendor patterns never see.
- **React Native / mobile vendor SDKs** catch binding modules (`@react-native-firebase/*`, `react-native-purchases`,
  `react-native-onesignal`) whose package names share no substring with the SDK they wrap. Like the LLM wrappers, the
  binding is never the finding - name the service behind it (Firebase, RevenueCat, OneSignal). A
  `@react-native-firebase/auth` import lands in both this group and Firebase; that is still one finding.

A file can therefore appear under several vendor groups (`api.stripe.com` hits both Stripe and the HTTP sweep). It still
produces **one** finding, naming every vendor involved - never one finding per group.

**Language coverage - do not read silence as cleanliness.** The patterns cover **JavaScript/TypeScript (including
React Native), Python, Java/Kotlin, Go, .NET/C#, Swift/Objective-C, PHP, Dart/Flutter, Clojure/Scala, and
CocoaPods/Gradle/pubspec manifests**. Step 1 also reads `Gemfile` and `Cargo.toml`, but **no pattern covers Ruby or
Rust import shapes**. For those two the scanner returning nothing means nothing was *searched for*, not that nothing is
there - grep explicitly for the vendor names Step 2 inventoried, in the language's own syntax (`Stripe::`,
`Twilio::REST`, `mongodb::`, `aws_sdk_`, ...). `references/dependency-patterns.md` lists the common shapes per
language. This is the same targeted sweep the Step 2 residual candidates need, so run them together.

**Three sweeps find what a coordinate-keyed pattern cannot**, and their hits need following up rather than citing
as-is:

- **Build-system indirection**: a module referencing `libs.playServicesMaps` or
  `projects.libraries.pushproviders.firebase` names no vendor at all - the coordinate lives once in
  `gradle/libs.versions.toml`, or behind an internal module. Count the alias references to size the blast radius, and
  watch for vendors entering as Gradle *plugins* (`apply plugin: 'com.google.firebase.crashlytics'`, a `classpath`
  entry) rather than dependencies.
- **Config-file wiring**: the scanner prints a `VENDOR CONFIG FILES PRESENT` section listing files whose *presence* is
  the evidence (`GoogleService-Info.plist`, `google-services.json`, `eas.json`, `app.config.js`). A Podfile with no
  Firebase entry beside an `AppDelegate.m` that calls `[FIRApp configure]` is a real dependency that manifest-only
  reasoning misses. Classify these as Bootstrap (R2) - coverage, not severity.
- **Expo/EAS**: `app.config.js` / `app.config.ts` is executable and overrides `app.json`, so read the dynamic config;
  and check the reverse direction too, since a declared `appcenter`/CodePush dependency with no source imports is a
  dead declaration rather than a finding.

### Step 3a - Triage the hits before reading them

Read the scanner's **HITS BY DIRECTORY** table before reading any hit. It aggregates every group's hits per directory
(and drills one level deeper into any tree with 200+ hits), which lets you classify whole trees in one decision instead
of reading thousands of near-identical lines.

- **Committed third-party trees** are the dominant noise source in large repos - a payment SDK committed under
  `includes/<vendor>/`, third-party libraries under `public/lib/`, minified vendor bundles under `Extensions/`. The
  scanner marks directories carrying `LICENSE`/`COPYING`/minified files. A vendored SDK tree is **evidence the vendor
  is used**, not hundreds of findings: classify it once, and do the call-site classification in *first-party* code.
- **Translation catalogs, fixtures, comments and changelogs** name vendors as text. Expect them;
  `references/triage-and-noise.md` T4 lists the collisions that recur (`amplitude` in shader code, `mongoose` as an
  embedded C web server, `segment` as audio segmentation, vendor names inside icon-name lists).
- **Aggregate when a vendor is everywhere.** If one vendor has more than roughly 10 first-party hit files inside one
  sub-project, that is *one* coupling with many call sites - write a single finding with a location count and three to
  five representative citations, and put the full file list in the File Index. Below that, keep one finding per file.
  Aggregate before Tier 2, so the verifier reviews substantive claims instead of near-duplicates.
- **Notebooks** (`.ipynb`) are JSON: cite the *cell*, not the JSON line number, and remember that a multi-line call
  split across `source` array elements can be present without matching. In an nbdev-style repo the notebooks are the
  source and the `.py` files are generated - audit the notebooks.

Read `references/triage-and-noise.md` in full whenever the scan returns more than a few hundred hits, or whenever the
directory table shows one tree dominating the total.

### Step 4 - Assign a tentative role (name/path heuristics only)

Apply **R2** of `references/classification-rules.md` - the Heuristic column only. In Tier 1 this is a *tentative* label:
apply the name/path signal and stop. Do NOT read call sites, follow imports, or perform the sole-referencer check (R2a)
- that cross-file work is Tier 2's job. When the heuristics are ambiguous, default to the more severe role (Violation)
and let Tier 2 downgrade it.

### Step 5 - Assign tentative severity

Apply **R3** of the rulebook. In Tier 1, mark the level as a guess by appending a `?` in the finding heading (e.g.
`[High?]`); Tier 2 removes the `?` when it confirms, or changes the level when it adjusts.

### Step 6 - Recognize acceptable patterns

Apply **R4** of the rulebook: AWS S3, standard protocols, OSI-approved datastores, vendor SDKs confined to their adapter,
type-only imports, dual-licensed libraries, and any client pointed at a self-hosted instance of a hostable service (an
LLM runtime, Sentry, PostHog, Supabase/PostgREST, Elasticsearch) are not findings. R4b covers self-hosted-but-coupled
services and R4c free hosted data APIs - both informational, neither a finding. R4 also carries the LLM
wrapper-attribution rule and the exclusions to the self-hosted-endpoint exception. When in doubt, flag and let the
user decide; document the ambiguity in the finding.

**The rulebook is the authority for Steps 4-6, and it is what the Tier 2 verifier reads.** Read
`references/classification-rules.md` in full before classifying - these three stubs tell you which rule applies, not what
it says.

### Step 7 - Write the draft report

Write `PLATFORM-DEPENDENCY-ANALYSIS.md` at the project root using the template below. This is the Tier 1 *draft*; Tier 2
edits it in place, so its structure must be stable:

- Set the header `Verification:` line to `pending`.
- Give each finding (one per grouped file) a **stable claim ID** `PDA-001`, `PDA-002`, ... in discovery order, and a
  `Status: UNVERIFIED` line. Keep the `### [PDA-NNN] [Severity?] ...` heading and the `Status:` line on their own lines,
  format-stable, so the verifier can rewrite them with exact-string edits.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- For findings that came from Step 2's **residual judgment pass** rather than a known pattern, state the license basis in
  the `Problem:` sentence - which service the dependency binds to and under what license (e.g. "`@sentry/node` is a
  client for Sentry's hosted service, licensed FSL, not OSI-approved"). Tier 2 then checks your reasoning instead of
  re-deriving the license from its own training data, which is frozen and often stale.
- **Do NOT write the executive-summary severity table or the File Index yet.** Leave both placeholder lines in place.
  They are computed LAST - after Tier 2 verification - because verdicts change the counts and the classifications. Until
  Tier 2 runs, the draft's severities are tentative (`?`); anything derived from them would be state that drifts.
- Compute `Files scanned:` with the command in the template rather than estimating it.
- **Group by sub-project when the repo has more than one** (workspace packages, `backend/` + `frontend/`, a Go lambda
  beside a Node service). Use `#### <sub-project>` headings inside Findings, and a `Sub-project` column in the File
  Index. A flat list across 40 workspace packages hides which team owns which coupling.
- **State coverage limits in the header** whenever something structural was not auditable: uninitialized submodules, a
  solution file enumerating projects absent from disk, an ecosystem with no pattern coverage, or a dependency inventory
  derived from imports because the repo has no manifests. An audit that quietly covers 10 percent of a platform and
  reads as complete is the worst outcome this skill has.

## Report Template

```markdown
# Platform Dependency Analysis

- Repository: <name>
- Analyzed at: <YYYY-MM-DD>
- Files scanned: <count>   <!-- compute it, do not estimate: `rg --files | wc -l` (respects .gitignore, works in any directory).
                              `git ls-files | wc -l` also works but counts only TRACKED files - it returns 0 in a repo whose
                              files are all still untracked, which would put a false "0" in the report. -->
- Languages: <list>
- Sub-projects: <list, or "single project">   <!-- workspace packages / backend+frontend split; omit if only one -->
- Dependency inventory: manifests (N read, depths <a-b>) | imports (no manifest present)
- Coverage limits: none   <!-- or: "15 submodules declared, all uninitialized - this audit covers only the
                               checked-out portion"; "no pattern coverage for Ruby - vendor names greped explicitly" -->
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

### [PDA-002] [High?] <Vendor> across <sub-project> (aggregate)
Status: UNVERIFIED
Claimed role: mixed - see representative sites

Locations: 47 files, 210 call sites in `core/` (full list in the File Index)
Representative:
- `core/server/services/mail/mailgun-provider.js:31` provider implementation
- `core/server/api/endpoints/members.js:88` direct call from an API handler
- `core/frontend/services/notify.js:12` direct call from view code

Problem: <one sentence>. Severity reflects the worst site (`.../members.js:88`).

Recommended fix: <one recommendation covering the set>.

Effort: S / M / L

---

### [PDA-003] [Medium?] <next finding>
Status: UNVERIFIED
...

## Acceptable Dependencies (informational)

- AWS S3 via `@aws-sdk/client-s3`: open protocol, swappable. No action.
- PostgreSQL via `pg`: open source. No action.
- `ms-rest-azure`: declared in `package.json`, zero source references - a dead declaration, not a coupling. Safe to remove.
- iText (dual-licensed AGPL or commercial): OSI option exists, so not a finding; a closed-source deployment needs the paid licence.

## Architecture Recommendations

1. <e.g. introduce `ports/` for interfaces; keep vendor adapters in `adapters/`>
2. <e.g. adopt a DI container or factory>
3. <e.g. add an ESLint or import-linter rule preventing vendor-SDK imports from `domain/`>

## File Index

<!-- FILE INDEX: do not fill in during Tier 1. Written at finalize from the final verdicts, like the
     severity table - a Tier 1 index would carry tentative severities that Tier 2 then changes, and
     duplicated state drifts. Final form:
     | Sub-project | File | Vendor | Classification | Severity |
     |---|---|---|---|---|
     | api | src/services/order.ts | Stripe | Domain logic with vendor call | Critical |
     | api | src/adapters/stripe-payment.adapter.ts | Stripe | Adapter | OK |
     (drop the Sub-project column when the repository has only one)
-->
_File index pending verification._
```

## Tier 2 - Verify

The Tier 1 draft is a set of *unverified guesses* from grep context. Tier 2 confirms, adjusts, or rejects each claim with
the call-site and cross-file analysis Tier 1 deliberately skipped. Run it before showing the report to the user.

Spawn **one** general-purpose subagent via the Agent tool. Key mechanics to respect:

- The subagent does **not** inherit this skill - it sees only the prompt you give it. The prompt points it at
  `references/classification-rules.md` and `references/dependency-patterns.md` by absolute path, and explicitly tells it
  **not** to read this `SKILL.md`: a fresh context reading the scan workflow, the report template, and its own spawn
  prompt would be following imperatives that contradict its job. Fill in the three `<...>` placeholders before spawning
  (skill dir, repo root, draft path).
- The subagent edits the draft in place with exact-string edits, so it depends on the format-stable heading, `Status:`,
  and `Claimed role:` lines Tier 1 produced. It must not touch the `Verification:` header line or the summary placeholder
  - those are yours to finalize.
- The Agent tool's final report is **not shown to the user**; you relay the outcome yourself (see Finalize).

Use this spawn prompt (verbatim, with placeholders filled):

```text
You are verifying a platform-dependency audit. A draft report already exists; your job is to
confirm, adjust, or reject each finding using call-site and cross-file analysis, and edit the
draft in place. You are NOT re-scanning the repo for new findings.

Repo root: <ABSOLUTE_PATH_TO_REPO_ROOT>   (run every repo-wide grep from here)

First, read these two files - they are the complete rules you need, and the only ones:
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/classification-rules.md  - the authoritative rulebook
  (R1 scope, R2 roles, R2a adapter test, R2b adapter layout conventions, R3 severity incl. the
  build-variant modifier, R4 acceptable patterns, R4a verdict vocabulary, R4b self-hosted but
  coupled, R4c free hosted data APIs, R5 endpoint resolution incl. R5a runtime provider
  registries, R6 what counts as real usage, R7 hardcoded credentials, R8 upstream forks).
  Read it in full before judging anything.
- <ABSOLUTE_PATH_TO_SKILL_DIR>/references/dependency-patterns.md  - vendor patterns, the dated
  license table, and LLM wrapper attribution.
Then read the draft report: <ABSOLUTE_PATH_TO_DRAFT>

Do NOT read the skill's SKILL.md - it contains the scan workflow and this prompt, none of which
apply to your job.

For EACH finding (each `### [PDA-NNN] ...` block), run this procedure:
  1. Open the flagged file at each cited `path:line` and confirm real vendor usage exists there,
     per R6 - SDK call/import, raw HTTP to a vendor endpoint, or a transitive LLM wrapper import
     all count. Do NOT reject a finding merely because it is not an SDK import. Cited lines that
     are a comment, a doc, or a test fixture string are false positives -> REJECTED.
  2. Adapter test (R2a - the check Tier 1 could not do): does the file (a) implement an interface
     or abstract class for that capability, AND (b) is it the ONLY place that vendor SDK is
     referenced for that capability? Run a repo-wide grep for the SDK import to settle (b). A
     file that looks like an adapter but whose SDK is imported by other files too is NOT a real
     adapter -> it is a violation. Mind R2a's note: a bypass that reaches the same vendor without
     the SDK is its own finding, not a reason to fail an otherwise clean adapter.
  3. Caller analysis: grep for importers of the flagged module. Check whether vendor types leak
     upward through its public surface (return types, params). A leak downgrades an otherwise-
     clean abstraction to Medium (R3).
  4. Clients of services that CAN be self-hosted - LLM SDKs (OpenAI/Anthropic/Gemini/Cohere/
     Mistral, including ones reached through a wrapper such as langchain_*, @ai-sdk/*,
     llama_index.llms.*, litellm), and equally Sentry, PostHog, Supabase, Elasticsearch, S3:

     4a. Wrapper attribution (R4). The wrapper library is MIT/Apache and is never itself the
         finding - re-title the finding after the proprietary model API it binds to. Then judge
         the shape: code written against a provider-agnostic type with the concrete provider
         chosen at composition time, or a litellm call whose model string comes from config, is
         acting AS the abstraction -> ADJUST down (or [OK], like a real adapter). `ChatOpenAI`
         imported straight into a use case, or a hardcoded proprietary model string in domain
         code, stays a finding.

     4b. Endpoint check (R4 + R5). Look for a `base_url`/`baseURL`/`endpoint`/DSN override where
         the client is constructed. R4's table lists which self-hosted targets reduce lock-in for
         which client - a Supabase client aimed at a self-hosted PostgREST is NOT BaaS lock-in,
         and a Sentry DSN pointing at a self-hosted instance is not sentry.io. If the endpoint is
         chosen at runtime from a database or a provider registry, apply R5a: describe the
         registry and judge each provider leg separately, rather than forcing one verdict. Self-hostable open-weight runtime (vLLM, Ollama, LiteLLM, LocalAI, TGI) ->
         reduced lock-in, REJECT/ADJUST like AWS S3. No override, another proprietary SaaS
         (Azure OpenAI, Groq, Together, Perplexity), or Bedrock/Vertex -> still a finding,
         re-attributed to the actual vendor. If the override reads an env var, walk R5's
         resolution ladder before deciding; if it does not resolve, the verdict is
         `ADJUSTED (endpoint indeterminate)` at Low or Medium with the ambiguity spelled out -
         NOT `REJECTED`.
  5. Before deciding, apply the modifiers: R3's build-variant rule (a vendor confined to a
     non-default flavour is contained - lower one level, name the flavour), R8 (in a fork of an
     upstream platform, keep the finding but mark it `inherited from upstream <project>` and
     adjust the recommendation, not the severity), and R7 (a hardcoded credential at a cited line
     is one clause inside the existing finding - never its own finding, never a severity change).

  6. Decide the verdict and severity per R2-R4, then edit the draft finding in place:
     - Rewrite the `Status:` line to exactly one of:
         Status: CONFIRMED
         Status: ADJUSTED (<short reason>)
         Status: REJECTED (<short reason>)
       Per R4a: REJECTED means the CLAIM was wrong (not real vendor usage -> `[N/A]`). Real usage
       that is simply acceptable - a genuine adapter, S3-only, a resolved self-hosted endpoint -
       is ADJUSTED with `[OK]`, not REJECTED.
     - In the heading `### [PDA-NNN] [Severity?] <title>`, remove the `?`. If you changed the
       level, replace it (e.g. `[High?]` -> `[Medium]`). For REJECTED, use `[N/A]`.
     - Fix `Claimed role:` if the role was wrong.
     - Add one line `Verification note: <what you found, citing path:line>`.

Rules of engagement:
- Edit ONLY the finding blocks. Do NOT edit the `- Verification:` header line, the Executive
  Summary, the severity-table placeholder, or the File Index - the main agent finalizes those.
- Use exact-string edits. Every finding carries an identical `Status: UNVERIFIED` line, so that
  line alone is NOT a unique anchor and the Edit tool will reject it. Always include the
  `### [PDA-NNN] ...` heading line in the `old_string` when rewriting a `Status:` line, and
  rewrite the heading and the status together in one edit. Never use replace_all - it would
  corrupt every other finding.
- Preserve every claim ID and the heading/`Status:` line structure.
- When genuinely uncertain after analysis, keep the finding (CONFIRMED or ADJUSTED) and say so
  in the Verification note; do not reject on doubt.
- Some findings cite a license basis in their `Problem:` line (e.g. "Sentry's server is FSL, not
  OSI-approved"). Do NOT overturn those from memory - your training data on vendor relicensing is
  frozen and frequently stale. The dated license table in dependency-patterns.md is the
  authority; if a claim contradicts it, adjust, and if neither settles it, keep the finding with
  an ambiguity note.

When done, return a plain-text list: one line per claim as `PDA-NNN: <VERDICT> - <one-clause reason>`.
```

**Default: a single verifier.** One subagent edits the whole draft sequentially, so there are no concurrent-edit
conflicts.

**Escalation (not the default): per-vendor fan-out.** Use it when the draft has **more than 30 findings or more than
12 distinct vendors** - past roughly that point a single verifier doing per-claim reads plus repo-wide greps starts
running out of context, and quality degrades silently.

Apply Step 3a's aggregation **before** counting against this threshold. A repo with 200 hit files and 12 vendors is a
dozen aggregate findings, not 200 claims; escalating on the un-aggregated number would make fan-out the default for
every large repository, which is not what it is for. If the count is still above the threshold after aggregating, the
repo genuinely has that much surface. To avoid concurrent edits to one file, fan-out verifiers must **return their
verdicts as text only** (the `PDA-NNN: VERDICT - reason` list) and NOT edit the draft; the main agent then applies every
edit itself. (A skill-driven Workflow-tool fan-out is an acceptable opt-in alternative for this case.)

## Finalize the report (main agent, after Tier 2)

The subagent's report is not shown to the user, and the draft still has a placeholder summary. After the verifier
returns, the main agent must:

1. Read the edited draft. If a fan-out was used, apply the returned verdicts to the draft now.
2. Recompute the severity counts by the finding's final severity label: count only findings whose heading carries a
   real severity (`[Critical]`, `[High]`, `[Medium]`, `[Low]`). Exclude `REJECTED` findings (`[N/A]`) and confirmed-
   acceptable ones (`[OK]`, e.g. a real adapter) - a `CONFIRMED` verdict does not by itself mean "counts as a violation".
   Render the real table into the placeholder (`_Severity table pending verification._`).
3. Render the **File Index** into its placeholder (`_File index pending verification._`) from the final verdicts - one
   row per file, including `[OK]` adapters and `[N/A]` rejections so the reader sees what was checked and cleared.
4. Write the **Executive Summary** prose now that the numbers are settled.
   Then sweep the findings for leftover Tier 1 placeholder text: the verifier is told to edit only status, heading,
   role, and its verification note, so a `Recommended fix: pending verification.` line in a claim it just CONFIRMED is
   yours to replace with the real recommendation.
5. Flip the header line to `- Verification: completed <YYYY-MM-DD>`.
6. Relay a concise summary to the user: counts by severity, how many claims were confirmed / adjusted / rejected, and
   the top one or two concerns - because the subagent's report never reaches them.
7. If available, produce a html version of the report using `marked`, first test if the tool is present

```bash
   command -v marked # if present, execute the conversion
   marked PLATFORM-DEPENDENCY-ANALYSIS.md > PLATFORM-DEPENDENCY-ANALYSIS.html
```

## Consolidating a multi-repository audit

A portfolio (a directory of independent repositories, an organization's projects) is audited **one repository at a
time** - the Step 1 guard enforces this - and then consolidated. Trigger this half when the user asks for a
consolidated, portfolio, or cross-repo view, or after finishing several per-repo runs.

**Inputs**: the finished `PLATFORM-DEPENDENCY-ANALYSIS.md` of each repository, each with a
`Verification: completed` header. A report still marked `pending` is not an input - finish or rerun it first, and if a
repository was never audited, say so rather than leaving a silent hole in the matrix.

**Do not re-scan.** Consolidation reads the finished reports and nothing else. Re-deriving findings from the code at
this stage produces numbers that disagree with the per-repo reports the user already has.

**Output**: `PLATFORM-DEPENDENCY-CONSOLIDATED.md` in the directory holding the repositories, containing:

- a header listing every repository included, with its report's date and its coverage limits;
- a **repo x severity matrix** (one row per repository, columns Critical/High/Medium/Low, plus a "no findings" marker
  for clean repos - the clean ones are a result, not an omission);
- **top vendors across the portfolio**: vendor, number of repositories, number of findings, so shared remediation is
  visible;
- **shared recommendations** - an abstraction several repositories need is worth building once;
- per-repo one-line summaries linking to each source report.

**Claim IDs stay traceable** by prefixing them with the repository name: `ghost/PDA-003`. Never renumber - a
consolidated ID must resolve back to a line in a per-repo report.

## When to Read the References

- Read `references/manifest-discovery.md` during **Step 1** whenever the repository is anything other than a single
  conventional project with its manifests at the root: nested repositories, submodules, workspaces, an unfamiliar
  manifest format, a thin or empty root manifest, or no manifest at all.
- Read `references/triage-and-noise.md` at **Step 3a** when the scan returns more than a few hundred hits, when one
  directory dominates the hit table, or when the repo contains notebooks - it carries the vendored-tree rule, the
  known pattern collisions, the aggregate-finding threshold, and the declared-vs-wired cross-check.
- Read `references/classification-rules.md` before Step 4 - it is the authority for roles, severity, and acceptable
  patterns, and it is the only rules file the Tier 2 verifier is given.
- Read `references/dependency-patterns.md` at the start of **Step 2** - both for the known-service list that drives Part 1 and for the "Commonly missed proprietary dependencies" table that makes Part 2's judgment pass cheap. It also carries the full pattern list and detection keywords used in Step 3.
- Read `references/abstraction-examples.md` while drafting "Recommended fix" sections in Step 7, so suggested code matches
  the shape (interface + implementation + DI wiring) appropriate to the target language. Its "Good Architecture Found in
  the Wild" section is also worth reading *before* classifying an unfamiliar layout: five real subsystems that a keyword
  grep flags as high-risk and that are in fact the abstraction this audit asks for.

## Output Discipline

- The report is the deliverable. Do not modify code unless the user explicitly asks for remediation in a follow-up.
- A report is final only after Tier 2. Do not present a draft that still carries `Status: UNVERIFIED` findings or a
  `Verification: pending` header as the finished audit; run the verifier and finalize first.
- Cite every claim with `path:line`. Do not paraphrase code without showing it.
- Keep each code snippet in the report to roughly ten lines.
- If the repo is clean (no violations), still emit the report so the user has documentation of that fact and the acceptable dependencies.
- Plain ASCII only - in the report, and in every file this skill ships or writes. No emojis, no typographic dashes or
  arrows, no other non-ASCII characters. Reports get pasted into trackers, diffed, and read in terminals where a
  stray em dash turns into mojibake; a rule the skill's own files break is a rule nobody follows.
