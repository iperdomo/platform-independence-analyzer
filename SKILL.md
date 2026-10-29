---
name: platform-independence-analyzer
description: Audit a code repository for direct dependencies on closed-source or proprietary services (Firebase, Google Maps, Stripe, Twilio, SendGrid, MongoDB, LLM/AI APIs like OpenAI, Anthropic, Gemini, Cohere, Mistral, vendor SDKs, cloud-specific functions, etc.) that lack an abstraction layer. Use when the user asks to evaluate platform independence, vendor lock-in, proprietary-dependency coupling, swappability of services, missing adapter/repository/port layers, or to produce a PLATFORM-DEPENDENCY-ANALYSIS.md report. Covers React Native / mobile repos, where proprietary services are reached through binding modules (@react-native-firebase, react-native-purchases, react-native-onesignal) and declared again in Podfile/build.gradle. Triggers on phrases such as "platform independence", "vendor lock-in", "proprietary dependency audit", "check for closed-source dependencies", "are we coupled to <vendor>", "can we swap <vendor>", "are we locked into OpenAI", "are we locked into Firebase", "LLM/AI vendor lock-in", "mobile vendor lock-in".
---

# Platform Independence Analyzer

Audit one repository for direct coupling between business logic and
proprietary or closed-source services. The deliverable is
`PLATFORM-DEPENDENCY-ANALYSIS.md` at the repository root: every coupling site
cited by `path:line`, classified, verified, and paired with a concrete
abstraction to introduce.

The whole audit answers one question: if we had to replace proprietary vendor
X tomorrow, which non-adapter files would change? Dependencies on OSI-licensed
open-source software are never findings, even when imported straight into
domain code - they can be forked or self-hosted without anyone's permission.
What counts is the license of the *service* a client binds to, not of the
client library (`mongoose` is MIT, MongoDB's server is SSPL, so it is a
finding). The full scope rules are R1 in `references/classification-rules.md`.

## How the audit runs

- **Tier 1 (Steps 1-7)** inventories dependencies, runs the bundled scanner,
  and writes a draft report. Every finding gets a claim ID and a tentative
  severity: `### [PDA-001] [High?] [UNVERIFIED] ...`.
- **Tier 2** is one fresh-context verifier subagent that confirms, adjusts or
  rejects each claim with call-site and cross-file analysis, editing the
  headings in place.
- **Finalize**: the main agent renders the summary, File Index and
  permalinks, and reports back to the user.

`references/classification-rules.md` is the authority for every judgment in
both tiers. `SKILL_DIR` below means this skill's directory, and `SCRATCH` a
scratch directory outside the repository (`mktemp -d`).

Hard stops - each one ends the run until the user acts:

- **Several repositories.** If `manifests.sh` exits 2 (no root `.git`, two or
  more child repositories), list them and ask the user to run the skill inside
  each one. A merged report mixes unrelated codebases into meaningless counts.
- **No ripgrep.** If a script exits 127, ask the user to install `rg`. Do not
  substitute another search tool: the findings claim to come from this exact,
  reproducible scan.

And one rule about tool output: always redirect script output to a file in
`SCRATCH` and Read the file. Bash output is capped, and a scan truncated
there looks complete while missing hits.

## Step 1 - Establish scope

```bash
bash SKILL_DIR/scripts/manifests.sh <repo-root> > SCRATCH/manifests.txt 2>&1; echo "exit=$?"
```

Read every manifest it lists, at every depth: in the calibration corpus 296 of
316 manifests sat at depth 2-4, and a thin root manifest (tool-config-only
`pyproject.toml`, a stray `package.json`) is a warning, not an answer. Read
`references/manifest-discovery.md` whenever the output shows more than one
manifest location, a thin or empty manifest, submodules, or no manifest at
all.

Record the languages, the architectural style if the layout shows one (it
decides what "domain" means), the sub-projects (findings are grouped by them),
and any coverage limit: uninitialized submodules, a solution file listing
projects absent from disk, no manifest at all.

Deployment and runtime config (compose, Helm, `serverless.yml`, CI, `eas.json`)
is evidence, never a finding source (R1): use it to resolve endpoints and see
which vendor products are enabled. If it is the repository's only vendor
coupling, the report says so explicitly.

## Step 2 - Inventory candidate dependencies

Build the candidate list from every manifest Step 1 found, tagged by
sub-project. Read `references/dependency-patterns.md` first.

1. **Known services.** Dependencies that match a vendor group in
   `references/patterns.tsv` or a service named in `dependency-patterns.md`.
2. **Everything else gets a judgment.** The pattern list is a closed
   allowlist and every list rots, so make an explicit proprietary-or-open call
   on each remaining dependency. Dismiss OSI-licensed frameworks, utilities
   and build tooling in bulk. For anything that wraps a hosted service (a
   database, search index, feature flags, error tracker, CMS, warehouse,
   queue, vector store, LLM gateway), judge the service's license; when it is
   unclear, treat it as proprietary. The "Commonly Missed Proprietary
   Dependencies" tables are a seed list, not an allowlist.
3. **Sources that are not manifests**: `.env.example` and friends, framework
   config (Laravel `config/services.php`), lock files for transitive SDKs,
   git-URL and extras-encoded dependencies, mobile service config
   (`google-services.json`), and vendor hosts hardcoded in source (Step 3's
   URL HOSTS section lists them). `manifest-discovery.md` D7 has the list.
   With no manifest at all, derive candidates from import statements (D8) and
   say so in the report.

For every proprietary candidate from item 2 or 3 that no built-in group
covers, add a line to `SCRATCH/extra.tsv` - tab-separated label, a regex for
the *import* name or host (`@sentry/`, `\bsnowflake\b`, `api\.rss2json\.com`),
and the license basis:

```text
Snowflake (residual)	\bsnowflake\b	proprietary warehouse, no OSI option
```

## Step 3 - Scan

```bash
bash SKILL_DIR/scripts/scan.sh --extra SCRATCH/extra.tsv <repo-root> > SCRATCH/scan.txt 2>&1; wc -l SCRATCH/scan.txt
```

(Omit `--extra` when Step 2 added nothing.) Read `SCRATCH/scan.txt`, in
chunks if it is large. The scanner prints its exclusions, a VENDOR CONFIG
FILES section, a URL HOSTS section, an exact HIT SUMMARY and a HITS BY
DIRECTORY table before any detail.

- URL HOSTS lists every host named in scanned files. Judge each one no vendor
  group explains: documentation and project-owned hosts are noise, a free
  public data API is informational (R4c), and anything token-gated or paid is
  a proprietary candidate - add it to `extra.tsv` and re-run the scan.

- A group larger than the detail cap ends with `# SAMPLED: showing N of M`.
  That sample keeps every directory represented; when a sampled group matters
  to a finding, re-run `rg` scoped to that directory for the full site list.
  A detail block shorter than its count *without* a SAMPLED line means the
  read was truncated - read the rest of the file.
- A residual candidate with no hits is declared but unused: list it under
  Acceptable Dependencies, not as a finding.
- A file can appear under several groups (`api.stripe.com` hits Stripe and the
  raw-HTTP group; `@react-native-firebase/auth` hits Firebase and the mobile
  group). It is still one finding, naming the service behind any wrapper or
  binding (R4).
- Three things the scan surfaces but cannot settle: build-system indirection
  (count Gradle catalog aliases and typed accessors to size the blast
  radius), config-file wiring (Bootstrap per R2 - coverage, not severity), and
  Expo's executable `app.config.js`, which overrides `app.json`.

## Step 3a - Triage before reading hits

Classify whole directories from HITS BY DIRECTORY first. A committed
third-party tree is evidence that the vendor is used, not hundreds of
findings: classify it once and do the call-site work in first-party code.
When one vendor has more than about ten first-party hit files in a
sub-project, write one aggregate finding with a location count and three to
five representative citations. Read `references/triage-and-noise.md` when the
scan has more than a few hundred hits, one directory dominates the table, or
the repository has notebooks.

## Steps 4-6 - Tentative classification

Read `references/classification-rules.md` in full, then for each finding:

- **Drop plain noise.** A hit whose own line is plainly a comment, prose, a
  UI string, or a collision from R6's table is not drafted. Anything less
  clear is drafted and left to Tier 2.
- **Role (R2)** from names, paths and the hit itself. Open a file when you
  need to cite the right line, but leave the cross-file checks - the R2a
  sole-referencer test, caller analysis, endpoint resolution (R5) - to Tier 2.
  When the role is ambiguous, pick the more severe one.
- **Severity (R3)**, marked tentative with `?`.
- **Acceptable patterns (R4)** - S3, open protocols, OSI datastores, a vendor
  SDK confined to its adapter, type-only imports, dual-licensed libraries, a
  client aimed at a self-hosted instance - go under Acceptable Dependencies,
  not Findings. When in doubt, flag it and state the ambiguity.

## Step 7 - Write the draft

Read `references/report-template.md` and write `PLATFORM-DEPENDENCY-ANALYSIS.md`
at the repository root in exactly that shape. Then:

```bash
python3 SKILL_DIR/scripts/report.py check <repo-root>/PLATFORM-DEPENDENCY-ANALYSIS.md
```

Fix every problem it lists before Tier 2.

## Tier 2 - Verify with exactly one subagent

Read `references/verifier-prompt.md`, fill in its three `<ABSOLUTE_PATH_...>`
placeholders, and spawn **one** general-purpose subagent with it. Always
exactly one verifier: never several in parallel, never a second one later,
and do not verify findings yourself alongside it. For a large repository,
Step 3a's aggregation is what keeps the claim count manageable.

When the verifier returns, run `report.py check`. If it lists findings still
marked UNVERIFIED, send the *same* verifier a message (SendMessage) asking it
to continue with those IDs - do not start a new one.

## Finalize

The verifier's reply never reaches the user, so finish the report yourself:

1. Render the severity table and mark the header completed:
   `python3 SKILL_DIR/scripts/report.py finalize <repo-root>/PLATFORM-DEPENDENCY-ANALYSIS.md`.
   It refuses while any finding is UNVERIFIED.
2. Replace the Executive Summary and File Index placeholders (the template
   describes both). Then read every Verification note: move what it says is
   acceptable into Acceptable Dependencies, and rewrite any Problem or
   Recommended fix line that no longer matches its verdict.
3. Run `report.py check` again; it must report 0 problems.
4. Pin every `path:line` reference to a permalink. The point is the checking:
   it aborts unless each reference exists at the pinned commit, is in range,
   and is not a blank line.

   ```bash
   R=<repo-root>/PLATFORM-DEPENDENCY-ANALYSIS.md
   python3 SKILL_DIR/scripts/linkify.py "$R"           # validate
   python3 SKILL_DIR/scripts/linkify.py --audit "$R"   # each ref + its source line
   python3 SKILL_DIR/scripts/linkify.py --write "$R"   # apply
   ```

   A validation error is a wrong line number in the report: fix the report,
   never the check (a reference landing on the blank line before its
   statement is the usual case). Read the `--audit` output before writing -
   only it shows a valid line in the wrong file. Each `skipped` entry is a
   reference that was not a full path; spell the path out. Add `--footnotes`
   only when the user asks for footnote-style references.
5. If `command -v marked` succeeds, render the HTML next to the report:
   `marked "$R" > <repo-root>/PLATFORM-DEPENDENCY-ANALYSIS.html`.
6. Tell the user the severity counts, how many claims were confirmed,
   adjusted and rejected (`report.py` prints the tally), and the top one or
   two concerns.

## Several repositories

To combine finished per-repository reports into a portfolio view, read
`references/consolidation.md`.

## Output discipline

- The report is the deliverable. Do not modify code unless the user asks for
  remediation in a follow-up.
- A report is finished only after Tier 2 and a clean `report.py check`.
- Cite every claim with its full `path:line`; keep snippets to about ten lines.
- A clean repository still gets a report, documenting that fact and the
  acceptable dependencies.
- Plain ASCII in the report and in every file this skill ships: no emojis,
  typographic dashes or arrows. Reports get pasted into trackers and terminals
  where those turn into mojibake.
