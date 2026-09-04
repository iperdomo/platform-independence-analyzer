#!/usr/bin/env bash
#
# scan.sh - deterministic vendor-SDK scan for the platform-independence-analyzer
# skill (Tier 1). Prints grouped `file:line:match` hits, one group per vendor,
# so the Tier 1 draft is a rendering of reproducible output instead of freehand
# grepping.
#
# Requires: ripgrep (rg) only.
#
# PATTERNS LIVE IN ONE PLACE: references/patterns.tsv. This script reads them at
# runtime, and `scan.sh --print-patterns` renders the same patterns as `rg`
# one-liners for a script-less run. Adding a vendor is a one-line change in the
# TSV - do not paste patterns into this file or into the reference docs.
#
# Language coverage: JS/TS (incl. React Native), Python, Java/Kotlin, Go,
# .NET/C#, Swift/Objective-C, PHP, Dart/Flutter, Clojure/Scala, and
# CocoaPods/Gradle/pubspec manifests. Ruby and Rust import shapes are NOT
# covered - no output for those ecosystems means nothing was searched for, not
# that the repo is clean. See SKILL.md Step 3.
#
# Every pattern runs under `rg -in`, so case carries no signal: `import firebase`
# matches Swift `import FirebaseCore`, Python `import firebase_admin`, and JS
# `import firebase from` alike. Do not write patterns that depend on case.
#
# Usage:
#   scripts/scan.sh [ROOT_DIR]        scan ROOT_DIR (defaults to ".")
#   scripts/scan.sh --print-patterns  print the rg one-liners and exit
#   PIA_PATTERNS=<file> scripts/scan.sh ...   use a different pattern table
#
# Output shape: a per-vendor HIT SUMMARY, then a HITS BY DIRECTORY triage table,
# then the grouped detail. The counts are always exact. Large groups print a
# per-directory SAMPLE of the detail and say so on a `# SAMPLED:` line - that is
# announced, not silent. A detail block shorter than its count with NO SAMPLED
# line means the output was truncated downstream and the draft would be silently
# incomplete. Redirect to a file and read that rather than piping to a tool with
# an output cap.
#
# Exit codes: 0 = ran (with or without hits); 2 = pattern table missing or empty;
# 127 = ripgrep not installed.
# ripgrep is a hard requirement - on 127 the audit stops and the user installs
# rg. Do not substitute another search path: findings must come from this exact
# reproducible scan.
#
# ripgrep respects .gitignore by default, so node_modules/dist/build/.venv/
# target/.next/coverage are already skipped when gitignored. The --glob
# exclusions below cover cases rg will not skip on its own (committed vendor/
# and Pods/ dirs, generated Xcode/Expo artifacts, lock files, and Markdown docs
# that mention vendor names in prose).

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="${PIA_PATTERNS:-$SCRIPT_DIR/../references/patterns.tsv}"

# Detail-output caps. The HIT SUMMARY counts are always complete and exact; only
# the printed detail is capped, and every cap is announced in the output. A repo
# with a committed vendor SDK can produce tens of thousands of hits in one group,
# and an unreadable 10MB scan file is its own failure mode. Sampling per
# directory (rather than head -N) keeps first-party hits visible when a vendored
# tree dominates a group. Set PIA_MAX_DETAIL=0 for no cap.
MAX_DETAIL_PER_GROUP="${PIA_MAX_DETAIL:-1500}"
MAX_DETAIL_PER_DIR="${PIA_MAX_DETAIL_PER_DIR:-10}"

PRINT_ONLY=0
if [ "${1:-}" = "--print-patterns" ]; then
  PRINT_ONLY=1
  shift
fi

ROOT="${1:-.}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required but was not found on PATH" >&2
  echo "install it (pacman -S ripgrep / apt install ripgrep / brew install ripgrep), then re-run" >&2
  exit 127
fi

if [ ! -r "$PATTERNS_FILE" ]; then
  echo "error: pattern table not found or unreadable: $PATTERNS_FILE" >&2
  echo "it ships with the skill at references/patterns.tsv; set PIA_PATTERNS to override" >&2
  exit 2
fi

# Load the pattern table: LABEL <TAB> PATTERN <TAB> NOTE, '#' comments ignored.
LABELS=()
PATTERNS=()
NOTES=()
while IFS=$'\t' read -r label pat note; do
  case "$label" in ''|'#'*) continue ;; esac
  [ -z "$pat" ] && continue
  LABELS+=("$label")
  PATTERNS+=("$pat")
  NOTES+=("${note:-}")
done < "$PATTERNS_FILE"

if [ "${#LABELS[@]}" -eq 0 ]; then
  echo "error: no patterns loaded from $PATTERNS_FILE" >&2
  exit 2
fi

if [ "$PRINT_ONLY" -eq 1 ]; then
  echo "# rg one-liners generated from $(basename "$PATTERNS_FILE") (${#LABELS[@]} groups)"
  echo "# Run from the repository root. Add the exclusions this script uses:"
  echo "#   --glob '!**/vendor/**' --glob '!**/Pods/**' --glob '!**/*.pbxproj' \\"
  echo "#   --glob '!**/.expo/**' --glob '!**/*.lock' --glob '!**/package-lock.json' \\"
  echo "#   --glob '!**/*.md' --glob '!**/PLATFORM-DEPENDENCY-ANALYSIS.*'"
  for i in "${!LABELS[@]}"; do
    echo
    echo "# ${LABELS[$i]}"
    [ -n "${NOTES[$i]}" ] && echo "#   note: ${NOTES[$i]}"
    esc="${PATTERNS[$i]//\'/\'\\\'\'}"
    printf "rg -in '%s'\n" "$esc"
  done
  exit 0
fi

EXCLUDES=(
  --glob '!**/vendor/**'
  --glob '!**/Pods/**'          # CocoaPods deps, committed in some iOS/RN repos
  --glob '!**/*.pbxproj'        # generated Xcode project; mirrors the Podfile
  --glob '!**/.expo/**'         # generated Expo cache
  --glob '!**/*.lock'
  --glob '!**/package-lock.json'
  --glob '!**/*.md'
  --glob '!**/*.orig'           # merge/patch leftovers restate whole files
  --glob '!**/*.rej'
  --glob '!**/PLATFORM-DEPENDENCY-ANALYSIS.*'
  # COMMITTED build output. rg skips these when they are gitignored, but repos do
  # commit them - a tracked dist/ full of bundled vendor code otherwise lands in
  # the draft as first-party usage.
  --glob '!**/dist/**'
  --glob '!**/build/**'
  --glob '!**/out/**'
  --glob '!**/*.min.js'
  --glob '!**/*.min.css'
  --glob '!**/*.bundle.js'
  # Committed third-party trees under names rg has no way to guess.
  --glob '!**/third_party/**'
  --glob '!**/thirdparty/**'
  --glob '!**/extlibs/**'
  --glob '!**/ExtLibs/**'
  # Translated UI strings: a locale catalog naming a vendor is prose, not usage.
  --glob '!**/locales/**'
  --glob '!**/*.po'
  --glob '!**/*.pot'
  --glob '!**/*.mo'
  --glob '!**/*.arb'
  --glob '!**/*.xlf'
  # Notebook checkpoints duplicate every cell of their notebook.
  --glob '!**/.ipynb_checkpoints/**'
)

# Printed with the results so a reader knows what silence means. Keep in sync
# with EXCLUDES above and with SKILL.md Step 1.
EXCLUDES_HUMAN="vendor/ Pods/ *.pbxproj *.orig *.rej .expo/ lock files *.md dist/ build/ out/ *.min.js *.min.css *.bundle.js third_party/ thirdparty/ extlibs/ locales/ *.po *.pot *.mo *.arb *.xlf .ipynb_checkpoints/ (plus everything .gitignore excludes)"

# Vendor config files whose PRESENCE is the evidence: their contents may name no
# vendor at all (eas.json, an app.config.js), so a content grep misses them. A
# hit here is wiring, not usage - Bootstrap per classification-rules R2.
CONFIG_GLOBS=(
  -g 'google-services.json' -g 'GoogleService-Info.plist' -g 'agconnect-services.json'
  -g 'firebase.json' -g '.firebaserc' -g 'sentry.properties' -g 'newrelic.properties'
  -g 'eas.json' -g 'app.config.js' -g 'app.config.ts' -g 'Podfile' -g 'capacitor.config.json'
  -g '.flutter-plugins-dependencies' -g 'gradle/libs.versions.toml'
)

echo "# platform-independence scan"
echo "# root: $ROOT"
echo "# patterns: $PATTERNS_FILE (${#LABELS[@]} groups)"
echo "# excluded: $EXCLUDES_HUMAN"
echo "# A vendor whose only trace is in an excluded path produces NO hits here."
echo

cfg="$(rg --files --hidden --glob '!**/node_modules/**' --glob '!**/Pods/**' \
      "${CONFIG_GLOBS[@]}" -- "$ROOT" 2>/dev/null | LC_ALL=C sort)"
if [ -n "$cfg" ]; then
  echo "== VENDOR CONFIG FILES PRESENT (by filename - wiring, not usage) =="
  printf '%s\n' "$cfg"
  echo "# A GoogleService-Info.plist or google-services.json proves Firebase is wired"
  echo "# even when no manifest declares it. app.config.js is executable and overrides"
  echo "# app.json - read it. eas.json means EAS Build/Update/Submit (proprietary)."
  echo
fi

found_any=0
total=0
groups=0
declare -a RESULTS=()
declare -a COUNTS=()
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  pat="${PATTERNS[$i]}"

  out="$(rg -in --no-heading --color=never --max-columns 200 --max-columns-preview \
        "${EXCLUDES[@]}" -e "$pat" -- "$ROOT")"
  rc=$?

  case "$rc" in
    0)
      found_any=1
      RESULTS[$i]="$out"
      COUNTS[$i]="$(printf '%s\n' "$out" | grep -c '')"
      total=$((total + COUNTS[i]))
      groups=$((groups + 1))
      ;;
    1)
      : # no matches for this vendor
      ;;
    *)
      printf 'warning: ripgrep failed (exit %d) for %s\n' "$rc" "$label" >&2
      ;;
  esac
done

# Summary first, so a truncated read still shows what SHOULD have been reported.
if [ "$found_any" -eq 1 ]; then
  echo "== HIT SUMMARY =="
  for i in "${!LABELS[@]}"; do
    [ -n "${COUNTS[$i]:-}" ] && printf '%6d  %s\n' "${COUNTS[$i]}" "${LABELS[$i]}"
  done
  printf '%6d  TOTAL hits across %d vendor groups\n' "$total" "$groups"
  echo "# If the detail below is shorter than these counts, output was truncated."
  echo

  # Directory breakdown: triage whole trees in one decision instead of reading
  # thousands of individual hits. A committed third-party tree shows up here as
  # one very large number, and is marked when marker files are found inside it.
  echo "== HITS BY DIRECTORY (triage these trees before reading hits) =="
  dirlist="$(printf '%s\n' "${RESULTS[@]}" \
    | sed -e 's/:.*//' -e "s|^${ROOT%/}/||" \
    | awk -F/ 'NF<=1 {print "(root)"; next} NF==2 {print $1"/"; next} {print $1"/"$2"/"}' \
    | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -25)"
  allpaths="$(printf '%s\n' "${RESULTS[@]}" | sed -e 's/:.*//' -e "s|^${ROOT%/}/||")"
  while read -r cnt dir; do
    [ -z "$cnt" ] && continue
    marks=""
    if [ "$dir" != "(root)" ] && [ -d "${ROOT%/}/$dir" ]; then
      if rg --files --hidden -g 'LICENSE*' -g 'COPYING*' -g '*.min.js' -g 'thirdpartylibs.xml' \
            -- "${ROOT%/}/$dir" 2>/dev/null | head -1 | grep -q .; then
        marks="  <- LICENSE/COPYING or minified file inside: check for a vendored third-party tree"
      fi
    fi
    printf '%6d  %s%s\n' "$cnt" "$dir" "$marks"
    # One level deeper for the trees big enough that "read every hit" is not a
    # plan. This is where a committed SDK usually becomes obvious by name.
    if [ "$cnt" -ge 200 ] && [ "$dir" != "(root)" ]; then
      printf '%s\n' "$allpaths" | grep -F "$dir" \
        | awk -F/ -v pre="$dir" 'NF>=4 {print pre $3"/"}' \
        | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | head -8 \
        | while read -r c2 d2; do printf '%6d      %s\n' "$c2" "$d2"; done
    fi
  done <<< "$dirlist"
  echo "# A vendored tree is evidence the vendor is USED; it is not hundreds of"
  echo "# findings. Classify the tree once, then read only first-party hits."
  echo
  for i in "${!LABELS[@]}"; do
    if [ -n "${RESULTS[$i]:-}" ]; then
      printf '== %s ==\n' "${LABELS[$i]}"
      [ -n "${NOTES[$i]}" ] && printf '# note: %s\n' "${NOTES[$i]}"
      if [ "$MAX_DETAIL_PER_GROUP" -gt 0 ] && [ "${COUNTS[$i]}" -gt "$MAX_DETAIL_PER_GROUP" ]; then
        # Quota by the first three path components, not by the immediate parent:
        # a vendored SDK spreads over hundreds of leaf directories and would
        # otherwise consume the whole cap before any first-party hit is printed.
        # Sample, do not truncate: up to N lines per directory (keyed on the
        # first three path components, because a vendored SDK spreads over
        # hundreds of leaf directories and would otherwise crowd out every
        # first-party hit). Every directory with hits stays represented.
        shown="$(printf '%s\n' "${RESULTS[$i]}" | awk -F: -v perdir="$MAX_DETAIL_PER_DIR" \
          -v root="${ROOT%/}/" \
          '{p=$1; if (index(p,root)==1) p=substr(p,length(root)+1);
            n2=split(p,a,"/"); k=a[1]; if (n2>2) k=k"/"a[2]; if (n2>3) k=k"/"a[3];
            if (++c[k]<=perdir) print}' | head -n "$MAX_DETAIL_PER_GROUP")"
        nshown="$(printf '%s\n' "$shown" | grep -c '')"
        printf '%s\n' "$shown"
        printf '# SAMPLED: showing %d of %d hits (up to %d per directory).\n' \
          "$nshown" "${COUNTS[$i]}" "$MAX_DETAIL_PER_DIR"
        printf '# The count above is exact - nothing was lost silently. Triage this\n'
        printf '# group with HITS BY DIRECTORY, then re-run scoped to a directory, or\n'
        printf '# set PIA_MAX_DETAIL=0 to print everything.\n\n'
      else
        printf '%s\n\n' "${RESULTS[$i]}"
      fi
    fi
  done
fi

if [ "$found_any" -eq 0 ]; then
  echo "No proprietary vendor SDK usage matched. Repo may be clean; still emit the report."
fi
