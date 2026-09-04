#!/usr/bin/env bash
#
# manifests.sh - recursive dependency-manifest discovery for the
# platform-independence-analyzer skill (Tier 1, Step 1).
#
# Why this exists: manifests almost never live only at the repository root.
# In a mixed corpus of ~50 real projects, 296 of 316 manifests sat at depth
# 2-4 (backend/, web/, app/, packages/<name>/), and several repos had a root
# manifest that declares nothing while every real vendor is declared deeper.
# A root-only read produces an empty candidate list, which silently disables
# the Step 2 residual pass and the Step 3 targeted sweeps.
#
# Requires: ripgrep (rg) only.
# Usage:    scripts/manifests.sh [ROOT_DIR]      (ROOT_DIR defaults to ".")
#
# Output sections:
#   REPO SHAPE       - single repo vs several nested repos (SKILL.md Step 1
#                      STOPs on the latter), submodule coverage
#   MANIFESTS        - every manifest found, with depth and an approximate
#                      declared-dependency count
#   DECOY WATCH      - root manifests that declare (almost) nothing while
#                      deeper manifests declare plenty
#   SUB-PROJECTS     - manifest counts per top-level directory, workspace
#                      declarations; drives per-sub-project reporting
#   NON-MANIFEST     - .env.example, PHP config, lock files: dependency
#                      evidence when a manifest is missing or silent
#   DEPLOYMENT       - compose/Helm/serverless/CI: NOT finding sources
#                      (out of scope, classification-rules R1), read only as
#                      endpoint-resolution and coverage evidence (R5)
#
# The `deps~` column is an approximation from a per-format regex, not a parse.
# It exists to separate "this manifest declares things" from "this manifest is
# empty or is tool config only". Do not quote it in the report.
#
# Exit codes: 0 = ran; 2 = several nested repositories found (audit must stop);
#             127 = ripgrep not installed.

set -uo pipefail

ROOT="${1:-.}"
ROOT="${ROOT%/}"
[ -z "$ROOT" ] && ROOT="/"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required but was not found on PATH" >&2
  echo "install it (pacman -S ripgrep / apt install ripgrep / brew install ripgrep), then re-run" >&2
  exit 127
fi

EXCLUDES=(
  -g '!**/node_modules/**'
  -g '!**/vendor/**'
  -g '!**/Pods/**'
  -g '!**/.git/**'
  -g '!**/dist/**'
  -g '!**/build/**'
  -g '!**/target/**'
  -g '!**/.venv/**'
  -g '!**/venv/**'
  -g '!**/__pycache__/**'
  -g '!**/coverage/**'
  -g '!**/.next/**'
  -g '!**/.cache/**'
  -g '!**/.expo/**'
  -g '!**/third_party/**'
  -g '!**/thirdparty/**'
  -g '!**/extlibs/**'
  -g '!**/ExtLibs/**'
  -g '!**/archetype-resources/**'   # Maven archetype TEMPLATES, not real deps
  -g '!**/maven-archetype/**'
  -g '!**/*.min.js'
)

MANIFEST_GLOBS=(
  # JS / TS
  -g 'package.json'
  # Python
  -g 'pyproject.toml' -g 'setup.py' -g 'setup.cfg' -g 'Pipfile'
  -g 'requirements*.txt' -g 'requirements*.in' -g 'requirements/*.txt'
  -g 'environment.yml' -g 'environment.yaml'
  # PHP / Ruby / Rust / Go
  -g 'composer.json' -g 'Gemfile' -g 'Cargo.toml' -g 'go.mod'
  # JVM
  -g 'pom.xml' -g 'build.gradle' -g 'build.gradle.kts'
  -g 'settings.gradle' -g 'settings.gradle.kts' -g 'libs.versions.toml'
  -g 'build.sbt'
  # .NET
  -g '*.csproj' -g '*.fsproj' -g '*.vbproj' -g '*.sln'
  -g 'packages.config' -g 'Directory.Build.props' -g 'Directory.Packages.props'
  -g 'paket.dependencies'
  # iOS / Swift
  -g 'Podfile' -g 'Package.swift' -g 'Package.resolved' -g 'project.yml'
  -g '*.pbxproj'
  # Dart / Flutter
  -g 'pubspec.yaml' -g 'pubspec.lock'
  # Clojure
  -g 'deps.edn' -g 'project.clj' -g 'shadow-cljs.edn'
  # Cordova / Capacitor
  -g 'capacitor.config.json' -g 'capacitor.config.ts' -g 'config.xml'
  -g 'variables.gradle'
  # Odoo addons
  -g '__manifest__.py'
)

NONMANIFEST_GLOBS=(
  -g '.env.example' -g '.env.sample' -g '.env.template' -g '.env.defaults' -g '.env.dist'
  -g 'poetry.lock' -g 'uv.lock' -g 'pnpm-lock.yaml' -g 'Podfile.lock'
  -g '.flutter-plugins-dependencies'
  -g 'google-services.json' -g 'GoogleService-Info.plist'
  -g 'config/services.php' -g 'config/mail.php' -g 'config/filesystems.php'
)

DEPLOY_GLOBS=(
  -g 'docker-compose*.yml' -g 'docker-compose*.yaml' -g 'compose*.yml'
  -g 'Chart.yaml' -g 'values*.yaml' -g 'serverless.yml' -g 'serverless.yaml'
  -g 'Procfile' -g 'netlify.toml' -g 'app.yaml' -g 'appveyor.yml'
  -g 'firebase.json' -g '.firebaserc' -g 'eas.json'
  -g 'app.json' -g 'app.config.js' -g 'app.config.ts'
  -g '.github/workflows/*.yml' -g '.github/workflows/*.yaml'
)

find_files() { # $@ = globs
  rg --files --hidden "${EXCLUDES[@]}" "$@" -- "$ROOT" 2>/dev/null | LC_ALL=C sort
}

rel() { printf '%s' "${1#"$ROOT"/}"; }

depth_of() { rel "$1" | awk -F/ '{print NF}'; }

fmt_of() {
  case "$(basename -- "$1")" in
    package.json) echo npm ;;
    composer.json) echo composer ;;
    pyproject.toml) echo pyproject ;;
    setup.py|setup.cfg) echo setuppy ;;
    Pipfile) echo pipfile ;;
    requirements*.txt|requirements*.in) echo pip ;;
    environment.yml|environment.yaml) echo conda ;;
    Gemfile) echo gem ;;
    Cargo.toml) echo cargo ;;
    go.mod) echo gomod ;;
    pom.xml) echo maven ;;
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts|variables.gradle) echo gradle ;;
    libs.versions.toml) echo gradlecatalog ;;
    build.sbt) echo sbt ;;
    *.csproj|*.fsproj|*.vbproj|Directory.Build.props|Directory.Packages.props) echo msbuild ;;
    packages.config) echo nugetcfg ;;
    *.sln) echo sln ;;
    paket.dependencies) echo paket ;;
    Podfile) echo podfile ;;
    Package.swift) echo swiftpm ;;
    Package.resolved) echo swiftpmlock ;;
    project.yml) echo xcodegen ;;
    *.pbxproj) echo pbxproj ;;
    pubspec.yaml|pubspec.lock) echo pubspec ;;
    deps.edn) echo depsedn ;;
    project.clj) echo lein ;;
    shadow-cljs.edn) echo shadowcljs ;;
    capacitor.config.*) echo capacitor ;;
    config.xml) echo cordova ;;
    __manifest__.py) echo odoo ;;
    *) echo other ;;
  esac
}

count_deps() { # $1 = path, $2 = fmt -> approximate declared-dependency count
  local f="$1" fmt="$2" n=""
  case "$fmt" in
    npm|composer)
      n=$(rg -c -e '"[^"]+"[[:space:]]*:[[:space:]]*"(\^|~|>=|<|=|[0-9]|\*|latest|file:|link:|git|github:|workspace:|npm:|dev-)' "$f" 2>/dev/null) ;;
    pyproject|cargo)
      n=$(rg -c -e '[<>~=!]=' -e '=[[:space:]]*"[\^~><=0-9*]' "$f" 2>/dev/null) ;;
    pip|pipfile)
      n=$(rg -c -e '^[[:space:]]*[^#[:space:]-]' "$f" 2>/dev/null) ;;
    setuppy)
      n=$(rg -c -e "^[[:space:]]*['\"][A-Za-z0-9_.\[\]-]+" "$f" 2>/dev/null) ;;
    conda)
      n=$(rg -c -e '^[[:space:]]*-[[:space:]]+[A-Za-z]' "$f" 2>/dev/null) ;;
    gem)
      n=$(rg -c -e '^[[:space:]]*gem[[:space:]]' "$f" 2>/dev/null) ;;
    gomod)
      n=$(rg -c -e '^[[:space:]]+[a-zA-Z0-9._-]+\.[a-z]+/' "$f" 2>/dev/null) ;;
    maven)
      n=$(rg -c -e '<artifactId>' "$f" 2>/dev/null) ;;
    gradle)
      n=$(rg -c -e '^[[:space:]]*(implementation|api|compileOnly|runtimeOnly|testImplementation|androidTestImplementation|classpath|kapt|ksp|annotationProcessor|debugImplementation|releaseImplementation)[[:space:](]' -e "^[[:space:]]*(id|apply plugin)[[:space:](']" "$f" 2>/dev/null) ;;
    gradlecatalog)
      n=$(rg -c -e '^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=' "$f" 2>/dev/null) ;;
    sbt)
      n=$(rg -c -e '%%?[[:space:]]*"' "$f" 2>/dev/null) ;;
    msbuild)
      n=$(rg -c -e 'PackageReference|PackageVersion' "$f" 2>/dev/null) ;;
    nugetcfg)
      n=$(rg -c -e '<package[[:space:]]' "$f" 2>/dev/null) ;;
    sln)
      n=$(rg -c -e '^Project\(' "$f" 2>/dev/null) ;;  # projects, not packages
    podfile)
      n=$(rg -c -e "^[[:space:]]*pod[[:space:]]" "$f" 2>/dev/null) ;;
    swiftpm)
      n=$(rg -c -e '\.package\(' "$f" 2>/dev/null) ;;
    swiftpmlock)
      n=$(rg -c -e '"identity"' "$f" 2>/dev/null) ;;
    xcodegen)
      n=$(rg -c -e '^[[:space:]]*(url|package|majorVersion|exactVersion|minorVersion):' "$f" 2>/dev/null) ;;
    pbxproj)
      n=$(rg -c -e 'XCRemoteSwiftPackageReference' "$f" 2>/dev/null) ;;
    pubspec)
      n=$(rg -c -e '^[[:space:]]{2}[a-z0-9_]+:' "$f" 2>/dev/null) ;;
    depsedn|lein|shadowcljs)
      n=$(rg -c -e '[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+' "$f" 2>/dev/null) ;;
    cordova)
      n=$(rg -c -e '<plugin[[:space:]]|cordova-plugin' "$f" 2>/dev/null) ;;
    odoo)
      n=$(rg -c -e "^[[:space:]]*['\"][a-z0-9_]+['\"]" "$f" 2>/dev/null) ;;
    *)
      n=$(rg -c -e '^[[:space:]]*[^#[:space:]]' "$f" 2>/dev/null) ;;
  esac
  [ -z "$n" ] && n=0
  printf '%s' "$n"
}

echo "# platform-independence manifest discovery"
echo "# root: $ROOT"
echo

# ---------------------------------------------------------------- REPO SHAPE
echo "== REPO SHAPE =="
root_git="no"
[ -e "$ROOT/.git" ] && root_git="yes"
echo "root .git: $root_git"

mapfile -t NESTED < <(find "$ROOT" -maxdepth 3 -name .git -not -path "$ROOT/.git" 2>/dev/null | LC_ALL=C sort)
echo "nested .git entries (excluding root): ${#NESTED[@]}"
for g in "${NESTED[@]}"; do
  echo "  $(rel "$(dirname -- "$g")")"
done

shape_rc=0
if [ "$root_git" = "no" ] && [ "${#NESTED[@]}" -ge 2 ]; then
  echo
  echo "VERDICT: MULTIPLE REPOSITORIES - STOP."
  echo "This directory is a container of independent repositories, not one repository."
  echo "Merging them into a single report yields meaningless severity counts and File"
  echo "Index. Run this skill once inside each repository above, then consolidate"
  echo "(SKILL.md 'Consolidating a multi-repository audit')."
  shape_rc=2
else
  echo "VERDICT: single repository (proceed)."
  if [ "$root_git" = "yes" ] && [ "${#NESTED[@]}" -ge 1 ]; then
    echo "NOTE: nested .git entries inside a repository are usually submodules or"
    echo "vendored checkouts - see submodule coverage below and state it in the report."
  fi
fi

if [ -f "$ROOT/.gitmodules" ]; then
  echo
  mapfile -t SUBPATHS < <(rg -N -o -r '$1' '^[[:space:]]*path[[:space:]]*=[[:space:]]*(.+)$' "$ROOT/.gitmodules" 2>/dev/null)
  echo ".gitmodules: ${#SUBPATHS[@]} submodule(s) declared"
  empty=0
  for s in "${SUBPATHS[@]}"; do
    s="${s%$'\r'}"
    if [ ! -e "$ROOT/$s" ] || [ -z "$(ls -A "$ROOT/$s" 2>/dev/null)" ]; then
      echo "  UNINITIALIZED: $s"
      empty=$((empty + 1))
    fi
  done
  if [ "$empty" -gt 0 ]; then
    echo "COVERAGE LIMIT: $empty of ${#SUBPATHS[@]} submodules are empty on disk."
    echo "The audit covers only the checked-out portion of this platform - say so in the"
    echo "report header (SKILL.md Step 7, 'Coverage limits')."
  fi
fi
echo

# ---------------------------------------------------------------- MANIFESTS
mapfile -t MANIFESTS < <(find_files "${MANIFEST_GLOBS[@]}")
echo "== MANIFESTS (${#MANIFESTS[@]}) =="
if [ "${#MANIFESTS[@]}" -eq 0 ]; then
  echo "NONE FOUND."
  echo "This repository declares no dependencies in any known manifest format."
  echo "Do NOT report it as dependency-free: derive the candidate list from import"
  echo "statements instead and say so in the report (SKILL.md Step 2, manifest-less"
  echo "repositories)."
else
  printf '%-6s %-7s %-14s %s\n' "depth" "deps~" "format" "path"
  declare -a DEPTHS=() DEPS=() FMTS=() RELS=()
  for m in "${MANIFESTS[@]}"; do
    f="$(fmt_of "$m")"; d="$(depth_of "$m")"; c="$(count_deps "$m" "$f")"; r="$(rel "$m")"
    DEPTHS+=("$d"); DEPS+=("$c"); FMTS+=("$f"); RELS+=("$r")
  done
  for i in "${!RELS[@]}"; do
    printf '%-6s %-7s %-14s %s\n' "${DEPTHS[$i]}" "${DEPS[$i]}" "${FMTS[$i]}" "${RELS[$i]}"
  done | LC_ALL=C sort -k1,1n -k4,4
  echo
  echo "ecosystem census:"
  printf '%s\n' "${FMTS[@]}" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | sed 's/^/  /'
  echo "A format that appears once in an otherwise single-ecosystem repo is suspect"
  echo "(leftover from a previous stack) - confirm before treating it as real."
fi
echo

# ---------------------------------------------------------------- DECOY WATCH
if [ "${#MANIFESTS[@]}" -gt 0 ]; then
  echo "== DECOY WATCH =="
  deep_max=0; deep_count=0
  for i in "${!RELS[@]}"; do
    if [ "${DEPTHS[$i]}" -gt 1 ]; then
      deep_count=$((deep_count + 1))
      [ "${DEPS[$i]}" -gt "$deep_max" ] && deep_max="${DEPS[$i]}"
    fi
  done
  flagged=0
  for i in "${!RELS[@]}"; do
    if [ "${DEPTHS[$i]}" -eq 1 ] && [ "${DEPS[$i]}" -le 3 ]; then
      echo "  THIN ROOT: ${RELS[$i]} declares ~${DEPS[$i]} dependencies."
      flagged=1
    fi
  done
  # A manifest from an ecosystem no other manifest uses is often a leftover from a
  # previous stack (a React Native package.json in a Flutter repo) rather than the
  # dependency surface. The census above is what makes it visible.
  shown=0
  for i in "${!RELS[@]}"; do
    if [ "${DEPS[$i]}" -eq 0 ]; then
      if [ "$shown" -lt 8 ]; then
        echo "  EMPTY: ${RELS[$i]} (${FMTS[$i]}) declares nothing."
      fi
      shown=$((shown + 1))
    fi
  done
  if [ "$shown" -gt 8 ]; then
    echo "  ... and $((shown - 8)) more empty manifests."
  fi
  if [ "$shown" -gt 0 ]; then
    echo "  Empty is sometimes correct and sometimes a trap: a Flutter ios/Podfile is"
    echo "  generated from .flutter-plugins-dependencies at build time and legitimately"
    echo "  lists nothing, while an empty .csproj may use central package management"
    echo "  (Directory.Packages.props) and an empty pyproject.toml may be tool config"
    echo "  only. Never conclude 'no dependencies' from an empty manifest - find where"
    echo "  that sub-project really declares them."
  fi
  if [ "$flagged" -eq 1 ] && [ "$deep_count" -gt 0 ]; then
    echo "  ...while $deep_count deeper manifest(s) declare up to ~$deep_max."
    echo "  A parsable root manifest is NOT proof the dependency surface was read."
    echo "  Known shapes: tool-config-only pyproject.toml (real deps in a pip"
    echo "  requirements file), CI-tooling-only Package.swift (app deps in XcodeGen"
    echo "  project.yml), a stray package.json in a Flutter repo."
  fi
  if [ "$flagged" -eq 0 ] && [ "$shown" -eq 0 ]; then
    echo "  Nothing suspicious: no thin root manifest, no empty manifest."
  fi
  echo
fi

# ---------------------------------------------------------------- SUB-PROJECTS
if [ "${#MANIFESTS[@]}" -gt 1 ]; then
  echo "== SUB-PROJECTS (manifests per top-level directory) =="
  for r in "${RELS[@]}"; do
    case "$r" in
      */*) printf '%s\n' "${r%%/*}/" ;;
      *)   printf '%s\n' "(root)" ;;
    esac
  done | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn
  for w in package.json pnpm-workspace.yaml lerna.json turbo.json go.work Cargo.toml settings.gradle settings.gradle.kts; do
    if [ -f "$ROOT/$w" ]; then
      if rg -q -e '"workspaces"' -e '^packages:' -e '\[workspace\]' -e '^[[:space:]]*include' -e '^use ' "$ROOT/$w" 2>/dev/null; then
        echo "workspace declaration: $w"
      fi
    fi
  done
  echo "Group findings and the File Index by sub-project when more than one is real"
  echo "(SKILL.md Step 7)."
  echo
fi

# ------------------------------------------------------- NON-MANIFEST EVIDENCE
mapfile -t NONMAN < <(find_files "${NONMANIFEST_GLOBS[@]}")
echo "== NON-MANIFEST DEPENDENCY EVIDENCE (${#NONMAN[@]}) =="
if [ "${#NONMAN[@]}" -eq 0 ]; then
  echo "  none"
else
  for m in "${NONMAN[@]}"; do echo "  $(rel "$m")"; done
fi
echo "Vendors are routinely declared ONLY here: SIP/STUN hosts and API tokens in"
echo ".env.example, a hardcoded gateway in a PHP config file, transitive vendor SDKs"
echo "in a lock file, Firebase presence proven only by google-services.json /"
echo "GoogleService-Info.plist. Read these when a manifest is missing or silent."
echo

# ------------------------------------------------------------ DEPLOYMENT FILES
mapfile -t DEPLOY < <(find_files "${DEPLOY_GLOBS[@]}")
echo "== DEPLOYMENT / RUNTIME CONFIG (${#DEPLOY[@]}) - NOT a finding source =="
if [ "${#DEPLOY[@]}" -eq 0 ]; then
  echo "  none"
else
  for m in "${DEPLOY[@]}"; do echo "  $(rel "$m")"; done
fi
echo "Infrastructure and deployment coupling is OUT OF SCOPE (classification-rules"
echo "R1). These files are read only as evidence: resolving an env-var endpoint (R5),"
echo "confirming which vendor products are enabled, and dynamic Expo config"
echo "(app.config.js overrides app.json)."

exit "$shape_rc"
