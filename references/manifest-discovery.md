# Manifest Discovery and Repository Shape

Everything Step 1 needs to answer two questions before any scanning happens:
**is this one repository?** and **where does it actually declare its
dependencies?** Get either wrong and the rest of the audit is confident
nonsense: a container of unrelated repos merged into one severity table, or a
root-only manifest read that returns an empty candidate list and silently
disables Step 2's residual pass and Step 3's targeted sweeps.

`scripts/manifests.sh` automates most of this. This file explains what its
output means, what it cannot decide for you, and how to work without it.

---

## D1. Repository shape - one repo per run

**This skill audits ONE repository per run.** A directory holding several
independent repositories is audited by running the skill once inside each of
them and then consolidating the finished reports (SKILL.md, "Consolidating a
multi-repository audit").

Decide the shape before scanning:

| Observation | Meaning | Action |
|---|---|---|
| `.git` at the root | One repository | Proceed |
| No root `.git`, two or more child directories each with `.git` | Container of repositories | **STOP.** List them, tell the user to run the skill inside each |
| Root `.git` plus nested `.git` entries | Submodules or vendored checkouts | Proceed, but report coverage (D2) |
| No `.git` anywhere | Exported source tree | Proceed; say in the report that no VCS metadata was available |

Merging repositories into one report is not a smaller version of the right
answer, it is a different and wrong one: severity counts stop meaning anything,
the File Index mixes unrelated projects, and one repo's clean abstraction gets
averaged against another's raw SDK calls.

## D2. Submodules and coverage honesty

An uninitialized submodule is an empty directory, and an empty directory scans
clean. Check `.gitmodules` against what is on disk. When submodules are
declared but empty - or when a solution/build file enumerates far more projects
than exist on disk - the audit covers a fraction of the platform, and the
report must say so in a `Coverage limits:` header line rather than implying
full coverage.

Seen in the wild: a server repo declaring 15 submodules, all empty, whose
`.sln` files enumerate 101 projects while only 11 `.csproj` exist on disk. The
honest statement is "this audit covers roughly 10 percent of the platform as
checked out", not a clean bill of health.

Same rule for any other structural blind spot: generated-at-build-time
dependency files, a private registry the manifests point at, an ecosystem with
no pattern coverage (see `dependency-patterns.md`). If it limits what could be
seen, it belongs in `Coverage limits:`.

## D3. Manifests live below the root - read recursively

Across a 50-repository corpus, **296 of 316 manifests sat at depth 2 to 4**.
Root-only reading is the single highest-impact failure this skill can make.
Representative shapes:

- Python service with all vendor SDKs in `app/requirements.txt` and
  `eth_worker/requirements.txt`, nothing at the root.
- Web app with `web/package.json` plus `backend/services/package.json`.
- pnpm monorepo with ~40 workspace manifests, every backend vendor in
  `core/package.json`.
- Clojure project declaring its AWS SDK only in `backend/deps.edn`.
- Node service with a root `package.json` whose real dependencies are one
  level down in `src/package.json`.
- Maven project with a single 2465-line `pom.xml` at depth 2 and no root pom.

Run `scripts/manifests.sh <root>` and read every manifest it lists, not just
the shallow ones. Without the script: `rg --files` with the globs in D4 and the
exclusions in D6.

## D4. Manifest formats to look for

Beyond the obvious `package.json` / `pyproject.toml` / `pom.xml` /
`build.gradle` / `go.mod` / `Gemfile` / `composer.json` / `Cargo.toml`:

| Ecosystem | Formats | Gotchas |
|---|---|---|
| Python | `requirements.txt`, `requirements.in`, `requirements-*.txt`, `requirements_*.txt`, `Pipfile`, `setup.py` / `setup.cfg` (`install_requires`), conda `environment.yml` / `environment.yaml` | `setup.py` deps can be conditional on env vars; a conda `environment.yml` is sometimes the ONLY manifest; `pyproject.toml` is often tool config only |
| .NET | `*.csproj` / `*.fsproj` / `*.vbproj` `PackageReference`, `packages.config`, `Directory.Build.props`, `Directory.Packages.props`, `*.sln` | A repo can have NO root manifest and only a `.sln`; three declaration styles routinely coexist in one repo |
| JVM | `build.gradle`, `build.gradle.kts`, `settings.gradle(.kts)`, `gradle/libs.versions.toml`, child `pom.xml` files | Version catalogs and dynamic module discovery hide coordinates (see `dependency-patterns.md`); EXCLUDE Maven archetype template poms under `archetype-resources/` |
| iOS / Swift | `Podfile` (any depth), `Package.swift`, `Package.resolved`, XcodeGen `project.yml`, `XCRemoteSwiftPackageReference` in `project.pbxproj` | `Package.swift` is sometimes CI tooling only while app deps live in `project.yml`; Podfiles are not always at `ios/Podfile` |
| Flutter | `pubspec.yaml`, `pubspec.lock` | iOS pods are generated from `.flutter-plugins-dependencies`, so the checked-in `Podfile` lists nothing - that silence is not evidence |
| Clojure / Scala | `deps.edn` (often several), `shadow-cljs.edn`, `project.clj`, `build.sbt` | A whole cloud SDK can be declared only in a nested `deps.edn`; a Scala fragment may ship with no `build.sbt` at all |
| Cordova / Capacitor | `capacitor.config.json`, generated `config.xml`, `variables.gradle` | Plugin names in `config.xml` name the vendor (ad networks, analytics) |
| Odoo | `__manifest__.py` (one per addon) | A single repo can hold many |

`.pbxproj` is a *manifest source* here (SwiftPM references) even though it is
excluded from the vendor *scan* as a generated artifact that restates the
Podfile. Read it for declarations; do not cite it as a usage site.

## D5. Decoy and empty manifests

A root manifest that parses is not proof the dependency surface was read.

- **Tool-config-only `pyproject.toml`**: black/ruff/pytest settings, real
  dependencies in `dependencies/pip/requirements.in`.
- **CI-tooling-only `Package.swift`**: the app's dependencies are in the
  XcodeGen `project.yml`.
- **Leftover from a previous stack**: a React Native `package.json` sitting in
  a Flutter repository. The ecosystem census in `manifests.sh` makes this
  visible - a format appearing once among many manifests of another ecosystem
  deserves a second look before it is trusted or dismissed.
- **Empty by design**: a Flutter `ios/Podfile`, a `settings.gradle` that only
  includes modules, a `.csproj` under central package management.

Rule: never conclude "no dependencies" from a thin or empty manifest. Find
where that sub-project really declares them, or say in the report that you
could not.

## D6. What to exclude while discovering

`node_modules`, `vendor`, `Pods`, `dist`, `build`, `target`, `.venv`,
`__pycache__`, `coverage`, `.next`, `.cache`, `.expo`, `third_party`,
`thirdparty`, `extlibs`, and Maven archetype template trees
(`**/archetype-resources/**`, `**/maven-archetype/**`).

A committed third-party tree carries its own manifests - a vendored PHP SDK
under `htdocs/includes/<vendor>/` or a bundled JS library each ships one. Those
manifests describe the *vendored library's* dependencies, not this project's.
Treat the vendored tree as evidence that the vendor is in use, and read the
project's own manifest for the declaration. See `triage-and-noise.md`.

## D7. Non-manifest dependency declarations

When no manifest exists, or the manifest is silent about a service that the
code clearly uses, these are first-class evidence:

- **`.env.example` / `.env.sample` / `.env.template`** - SIP/STUN hosts, vendor
  API keys, and third-party gateways are routinely declared only here.
- **Framework config files** - Laravel `config/services.php` and
  `config/mail.php` driver blocks; a PHP config file hardcoding a third-party
  messaging gateway URL.
- **Lock files** (`poetry.lock`, `uv.lock`, `pnpm-lock.yaml`, `Podfile.lock`) -
  the only place a *transitive* vendor SDK appears. Use them to explain a
  source hit whose package is not in any manifest; do not inventory them
  wholesale.
- **Git-URL dependencies** (`pkg @ git+https://...`) - name matching against a
  registry finds nothing; read the URL.
- **Extras-encoded dependencies** - `django-storages[azure,boto3]`, or an
  optional-extras block (`sentry = [...]`). A plain "read the dependencies
  array" pass misses every one of them.
- **Mobile service config files** - `google-services.json`,
  `GoogleService-Info.plist` prove Firebase is wired even when no manifest
  mentions it.

## D8. Manifest-less repositories

Some repositories declare nothing anywhere: a directory of Python modules, a
Scala fragment with no build file. These currently audit as "no dependencies"
while depending on a proprietary datastore through plain imports.

Rule: when no manifest exists, derive the candidate list from **import
statements**, and state in the report that the dependency inventory came from
imports rather than declarations. Useful sweeps:

```bash
rg -n --no-heading -e '^\s*(import|from)\s+\w+' -g '*.py' .
rg -n --no-heading -e '^\s*import\s+' -g '*.scala' -g '*.kt' -g '*.java' .
rg -n --no-heading -e '^\s*\(:require|^\s*\(require' -g '*.clj' -g '*.cljs' .
rg -n --no-heading -e '^\s*(use|require)\s' -g '*.php' -g '*.rs' .
```

Then aggregate the distinct top-level module names and run them through Step
2's proprietary-or-open judgment exactly as if they had been declared.

## D9. Sub-projects inside one repository

Workspaces are not nested repositories - they stay in one audit, but a flat
finding list loses their structure. Identify sub-projects from the manifest
layout (`manifests.sh` prints manifest counts per top-level directory) and from
workspace declarations: `"workspaces"` in `package.json`,
`pnpm-workspace.yaml`, `lerna.json`, `turbo.json`, `go.work`, Cargo
`[workspace]`, `settings.gradle` includes, a multi-module `pom.xml`.

When more than one real sub-project exists, group the findings and the File
Index by sub-project, and let the `Languages:` header carry the per-sub-project
breakdown rather than one merged list. A finding in a frontend workspace and a
finding in a Go lambda are not the same risk to the same team.

## D10. Deployment and runtime config: evidence, not findings

`docker-compose*.yml`, Helm `Chart.yaml` / `values.yaml`, `serverless.yml`,
`Procfile`, `netlify.toml`, `firebase.json`, `app.yaml`, CI workflows and
`eas.json` are **out of scope as finding sources** (classification-rules R1).
Read them anyway, for three things:

1. **Endpoint resolution** (R5): an `ollama` or `vllm` service next to the app
   in compose settles an otherwise indeterminate `base_url`.
2. **Coverage**: they reveal which vendor products are actually enabled.
3. **Dynamic config**: `app.config.js` / `app.config.ts` is executable and
   overrides `app.json`; reading `app.json` alone is misleading.

A repository whose only vendor coupling lives in deployment files therefore
reports **no code-level findings** - state that explicitly, with the coupling
named in one informational sentence, so the clean result is visibly deliberate
rather than an artifact of not looking.
