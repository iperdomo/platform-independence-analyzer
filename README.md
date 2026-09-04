# Platform Independence Analyzer

A Claude Code skill that audits a repository for direct coupling between
business logic and proprietary or closed-source services (Firebase, Google
Maps, Stripe, Twilio, SendGrid, MongoDB Atlas, vendor SDKs, cloud-specific
functions, and similar). The skill produces a `PLATFORM-DEPENDENCY-ANALYSIS.md`
report at the project root that names every coupling site by `file:line`,
classifies its severity, and recommends a concrete abstraction.

## What it checks

- Domain or business code that imports a proprietary SDK directly instead of
  going through an adapter, port, repository, provider, or gateway.
- Vendor types leaking through public interfaces.
- Tests that mock a vendor SDK directly rather than an abstraction.
- Declared dependencies in manifests that point at proprietary services -
  found **recursively**, because manifests rarely live only at the repository
  root (`web/package.json`, `backend/deps.edn`, `app/requirements.txt`, a
  single `pom.xml` at depth 2). Covered formats include npm, PyPI
  (`requirements*.txt`/`.in`, `Pipfile`, `setup.py`, conda `environment.yml`),
  Composer, Gradle (incl. `*.kts` and `gradle/libs.versions.toml` catalogs),
  Maven, Go, Cargo, Bundler, .NET (`*.csproj`, `packages.config`,
  `Directory.Packages.props`, `*.sln`), CocoaPods, SwiftPM, XcodeGen,
  `pubspec.yaml`, `deps.edn`, Cordova/Capacitor, and Odoo `__manifest__.py`.
- Dependencies declared **outside** any manifest: `.env.example`, Laravel
  `config/services.php`, lock files, git-URL dependencies, extras-encoded
  dependencies, and mobile service config (`google-services.json`,
  `GoogleService-Info.plist`). Repositories with no manifest at all are
  inventoried from their import statements instead of being reported as
  dependency-free.
- Vendors that enter through the **build system** rather than a dependency
  line: Gradle version-catalog aliases, typed project accessors, and plugins
  (`apply plugin: 'com.google.firebase.crashlytics'`), plus config-file-only
  wiring - an iOS `Podfile` naming no Firebase pod while `AppDelegate.m` calls
  `[FIRApp configure]`.
- Proprietary LLM/AI SaaS APIs (OpenAI, Anthropic, Gemini, Cohere, Mistral)
  used directly from business code, and hosted AI services well beyond them:
  Replicate, fal.ai, Modal, Deepgram, ElevenLabs, Groq, Fireworks, OpenRouter,
  HuggingFace hosted inference, Roboflow, ClearML, Langfuse, ML Kit, Google
  Cloud Speech/Translate/Vision, Azure Cognitive Services, and regional
  providers such as Sarvam, GhanaNLP and Lelapa.
- Any client pointed at a **self-hosted instance** of a hostable service is
  treated like the S3 case - reduced lock-in, not flagged - but only when the
  endpoint is actually resolvable from the repo. That rule is not LLM-specific:
  it covers vLLM/Ollama/LiteLLM behind an `openai` client, a self-hosted Sentry
  DSN, self-hosted PostHog, a Supabase client used purely as a PostgREST client
  against your own Postgres, and OpenSearch behind an Elasticsearch client. A
  bare `os.environ["LLM_BASE_URL"]` with no discoverable default stays a
  finding at reduced severity, with the ambiguity noted. Endpoints chosen at
  runtime from a database or a provider registry get their own verdict path:
  the registry is described and each provider leg judged separately.
- Whole classes of service the first version of this skill never looked for:
  payments beyond Stripe (M-Pesa/Daraja, Flutterwave, Paystack, Razorpay,
  PayPal), email beyond SendGrid (Mailgun, Postmark, Mailchimp, SES), SMS and
  chat beyond Twilio (Africa's Talking, MessageBird, Clickatell, WhatsApp
  Business Cloud, Telegram, Slack), error tracking, realtime SaaS, geospatial
  (Mapbox, ArcGIS, Earth Engine, HERE), captcha and analytics tags, blockchain
  RPC and ledgers (Infura, Alchemy, AWS QLDB), and proprietary database drivers
  (Oracle, SQL Server).
- Vendor APIs reached without an SDK at all - raw `fetch`/`httpx`/`requests`
  calls to `api.stripe.com`, `api.openai.com`, `*.googleapis.com`, and friends.
- LLM wrapper SDKs (LangChain, LlamaIndex, Vercel AI SDK, LiteLLM), where the
  vendor SDK is a transitive dependency. The wrapper is not the finding; the
  model API behind it is.
- React Native / mobile binding modules (`@react-native-firebase/*`,
  `react-native-purchases`, `react-native-onesignal`,
  `@stripe/stripe-react-native`, `react-native-branch`, ...), plus the native
  half an RN audit usually misses: `pod 'Firebase/...'` in the Podfile,
  `com.google.gms.google-services` in Gradle, `import FirebaseCore` in Swift.
  Same rule as the LLM wrappers - the MIT binding is not the finding, the
  service behind it is (Firebase, RevenueCat, OneSignal). React Native itself
  and the Expo SDK are open source and never flagged.

Pattern coverage is JavaScript/TypeScript (including React Native), Python,
Java/Kotlin, Go, .NET/C#, Swift/Objective-C, PHP, Dart/Flutter, Clojure/Scala,
and CocoaPods/Gradle/pubspec manifests. **Ruby and Rust** manifests are still
inventoried and judged, but their import shapes are not pattern-matched - the
audit greps for those vendor names explicitly instead of assuming a silent scan
means a clean repo.

## What it does not flag

- OSI-approved open-source dependencies (PostgreSQL, MySQL, SQLite, Redis,
  Valkey, Cassandra, ...) and open protocols (HTTP, SMTP, OAuth/OIDC, gRPC,
  S3 API).
- Open mapping stacks - MapLibre, Leaflet, OpenLayers, osmdroid, OSM tiles.
  A repository carrying both a Mapbox adapter and an osmdroid adapter behind
  one interface is demonstrating good architecture, not two couplings.
- Dual-licensed libraries (iText, JasperReports, Highcharts): an OSI option
  exists, so they are recorded informationally with a note that a closed-source
  deployment needs the paid licence.
- Services the project self-hosts (Ollama, Asterisk, PostgREST) and free
  open-data APIs (Open-Meteo, Nominatim) - informational only. A token-gated or
  paid API is an ordinary finding.
- **Infrastructure and deployment coupling** (`serverless.yml`, Helm, compose
  files, CI workflows, `Procfile`, `firebase.json`) is deliberately out of
  scope: this audit measures the code's coupling to proprietary services, not
  where it is deployed. Those files are still read as evidence - to resolve an
  endpoint, or to see which vendor products are enabled - and a repository
  whose only coupling lives there is reported as clean *with that stated
  explicitly*.
- Platform rails (App Store / Play billing, APNs and FCM as push transports,
  platform sign-in SDKs) are reported, with the honest note that an adapter
  contains the blast radius without removing a coupling you cannot architect
  away while shipping on that platform.

## How it works: a two-tier audit

The skill audits **one repository per run**. Pointed at a directory that holds
several independent repositories, it stops and asks you to run it inside each
one, then offers a consolidation pass that builds a portfolio report from the
finished per-repo reports without re-scanning.

The skill runs in two tiers to keep classification honest:

1. **Tier 1 - Scan (draft).** A cheap mechanical pass inventories manifests,
   greps for vendor usage, and writes a *draft* report. Every finding gets a
   stable claim ID (`PDA-001`, `PDA-002`, ...) and is marked `Status:
   UNVERIFIED`; its severity is tentative (shown with a trailing `?`, e.g.
   `[High?]`) because it is guessed from file names and paths alone.
2. **Tier 2 - Verify.** A fresh-context subagent reads each flagged call site,
   runs the cross-file checks Tier 1 skips (does a file *really* wrap a vendor,
   or is the SDK imported elsewhere too?), and marks each claim `CONFIRMED`,
   `ADJUSTED`, or `REJECTED`. The main agent then recomputes the severity table
   from the verified findings and flips the report header to `Verification:
   completed`.

An intermediate report containing `Status: UNVERIFIED` findings or a
`Verification: pending` header is a draft, not the finished audit - the skill
runs Tier 2 and finalizes before presenting results.

Between the two, Tier 1 triages. On a large codebase most hits come from
committed third-party trees - a vendored payment SDK, a bundled library
directory - and the scanner's per-directory table lets those be classified in
one decision instead of read line by line. A vendored SDK tree is evidence the
vendor is used, not hundreds of findings; when one vendor appears across many
first-party files in a sub-project, the report carries a single aggregate
finding with a location count and representative citations.

## What it produces

A single `PLATFORM-DEPENDENCY-ANALYSIS.md` file containing:

- A header line recording verification status (`pending` while drafting,
  `completed <date>` once verified).
- Executive summary with a severity count table (Critical / High / Medium /
  Low), computed after verification.
- One section per finding, each with a claim ID, a `Status:` line, exact
  `path:line` locations, and a recommended fix.
- A list of acceptable dependencies (informational).
- Architecture recommendations.
- A file index mapping every touched file to vendor, classification, and
  severity.

The skill does not modify source code. Remediation is a separate, explicit
follow-up.

## Requirements

- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) **must** be installed
  and available on `PATH`. The skill uses `rg` to locate vendor SDK call sites
  across the repository, and the bundled `scripts/scan.sh` requires it.

  Without `rg` the audit does not run. The scanner exits 127 and the skill stops
  and asks you to install it rather than falling back to a different search
  path - a vendor-lock-in audit is only as trustworthy as the completeness of
  its scan, and silently swapping the search engine underneath it would make
  results non-reproducible.

  Install on common systems:

  ```
  # Arch / Manjaro
  sudo pacman -S ripgrep

  # Debian / Ubuntu
  sudo apt install ripgrep

  # macOS (Homebrew)
  brew install ripgrep

  # Fedora
  sudo dnf install ripgrep
  ```

  Verify with `rg --version`.

  The skill bundles two ripgrep-only scripts, both usable on their own:

  - `bash scripts/manifests.sh <repo-root>` - repository shape (single repo vs
    a container of repos, submodule coverage), every manifest found recursively
    with its depth and an approximate dependency count, decoy/empty manifests,
    sub-projects, and non-manifest dependency evidence. Exits 2 when the
    directory holds several repositories.
  - `bash scripts/scan.sh <repo-root>` - the vendor scan: an exact per-group
    HIT SUMMARY, a HITS BY DIRECTORY triage table, then grouped
    `file:line:match` detail. Large groups print a per-directory *sample* of
    the detail and say so; the counts are always exact.

  All vendor patterns live in one place, `references/patterns.tsv` (label,
  ripgrep regex, judgment note). `bash scripts/scan.sh --print-patterns`
  renders them as ready-to-paste `rg` one-liners, so a script-less run uses the
  same patterns rather than hand-written ones. Adding a vendor is a one-line
  change in the TSV.

## Install locally in Claude Code

Claude Code loads skills from `~/.claude/skills/<skill-name>/`. To install
this skill for your user account, place the folder there:

```
git clone <this-repo-url> ~/.claude/skills/platform-independence-analyzer
```

Or, if you already have the folder elsewhere, symlink it:

```
ln -s /path/to/platform-independence-analyzer ~/.claude/skills/platform-independence-analyzer
```

The directory must contain `SKILL.md` at its root. After installation the
layout should look like:

```
~/.claude/skills/platform-independence-analyzer/
  SKILL.md
  README.md
  LICENSE.md
  references/
    classification-rules.md      rules R1-R8: scope, roles, severity, acceptable patterns
    dependency-patterns.md       vendor classes, licence tables, per-language shapes
    manifest-discovery.md        repository shape, manifest formats, decoys, coverage limits
    triage-and-noise.md          vendored trees, collisions, large-repo strategy, notebooks
    abstraction-examples.md      how to abstract, plus real good architecture from the wild
    patterns.tsv                 the single source of truth for every scan pattern
  scripts/
    manifests.sh                 recursive manifest + repository-shape discovery
    scan.sh                      the vendor scan (reads patterns.tsv at runtime)
```

Restart Claude Code (or start a new session) so the skill is picked up. No
`settings.json` changes are required; Claude Code discovers skills in
`~/.claude/skills/` automatically.

To install the skill only for a single project instead of globally, drop the
folder at `<project>/.claude/skills/platform-independence-analyzer/` and it
will be available when Claude Code runs in that project.

## Use it

Open Claude Code at the repository root you want to audit and ask in plain
English. The skill triggers on phrases like:

- "Audit this repo for platform independence."
- "Check for vendor lock-in."
- "Are we coupled to Firebase?"
- "Can we swap Stripe out?"
- "Run a proprietary-dependency audit and write the report."

Example session:

```
$ cd ~/code/my-service
$ claude
> Audit this repository for vendor lock-in and produce the report.
```

Claude will scan manifests, grep for known vendor patterns, and write a draft
`PLATFORM-DEPENDENCY-ANALYSIS.md` (Tier 1), then spawn a verifier subagent to
confirm or correct each finding (Tier 2) and finalize the report with a
verified severity table. Review the finished report, decide which findings to
act on, and then ask Claude to implement the recommended adapters in a
follow-up turn.

## Verify it is loaded

In a Claude Code session, type `/` to list available skills, or simply ask:

```
> What skills do you have available?
```

`platform-independence-analyzer` should appear in the list with the
description above.
