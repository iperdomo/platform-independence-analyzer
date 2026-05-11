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
  `composer.json`, `Cargo.toml`) that point at proprietary services.

OSI-approved open-source dependencies (PostgreSQL, MySQL, SQLite, Redis,
Valkey, Cassandra, etc.) and open protocols (HTTP, SMTP, OAuth, gRPC, S3 API)
are treated as acceptable and are not flagged.

## What it produces

A single `PLATFORM-DEPENDENCY-ANALYSIS.md` file containing:

- Executive summary with a severity count table (Critical / High / Medium / Low).
- One section per finding, each citing exact `path:line` locations and a
  recommended fix.
- A list of acceptable dependencies (informational).
- Architecture recommendations.
- A file index mapping every touched file to vendor, classification, and
  severity.

The skill does not modify source code. Remediation is a separate, explicit
follow-up.

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
    dependency-patterns.md
    abstraction-examples.md
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

Claude will scan manifests, grep for known vendor patterns, classify each
hit, and write `PLATFORM-DEPENDENCY-ANALYSIS.md` at the project root. Review
the report, decide which findings to act on, and then ask Claude to
implement the recommended adapters in a follow-up turn.

## Verify it is loaded

In a Claude Code session, type `/` to list available skills, or simply ask:

```
> What skills do you have available?
```

`platform-independence-analyzer` should appear in the list with the
description above.
