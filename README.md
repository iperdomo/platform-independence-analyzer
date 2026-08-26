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
- Declared dependencies in manifests (`package.json`, `pyproject.toml`,
  `requirements.txt`, `pom.xml`, `build.gradle`, `go.mod`, `Gemfile`,
  `composer.json`, `Cargo.toml`, `ios/Podfile`) that point at proprietary
  services.
- Proprietary LLM/AI SaaS APIs (OpenAI, Anthropic, Gemini, Cohere, Mistral)
  used directly from business code. An LLM SDK pointed at a self-hostable,
  OpenAI-compatible endpoint via `base_url` (vLLM, Ollama, LiteLLM, LocalAI,
  TGI) is treated like the S3 case - reduced lock-in, not flagged - but only
  when the endpoint is actually resolvable from the repo. A bare
  `os.environ["LLM_BASE_URL"]` with no discoverable default stays a finding at
  reduced severity, with the ambiguity noted.
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
Java/Kotlin, Go, .NET/C#, Swift/Objective-C, and CocoaPods/Gradle manifests.
Ruby, PHP, Rust, and Dart/Flutter manifests are still inventoried and judged,
but their import shapes are not pattern-matched - the audit greps for those
vendor names explicitly instead of assuming a silent scan means a clean repo.
Expo/EAS hosted services (EAS Build/Update/Submit, Expo push) are the other
deliberate gap and get the same explicit treatment.

OSI-approved open-source dependencies (PostgreSQL, MySQL, SQLite, Redis,
Valkey, Cassandra, etc.) and open protocols (HTTP, SMTP, OAuth, gRPC, S3 API)
are treated as acceptable and are not flagged.

## How it works: a two-tier audit

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

  The skill bundles `scripts/scan.sh`, a deterministic ripgrep-only scanner that
  runs every vendor pattern and prints grouped `file:line:match` hits. Tier 1
  runs it when present (falling back to freehand ripgrep otherwise). It needs
  nothing beyond `rg`; run it directly with
  `bash scripts/scan.sh <repo-root>` if you want the raw hit list.

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
    classification-rules.md
    dependency-patterns.md
    abstraction-examples.md
  scripts/
    scan.sh
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
