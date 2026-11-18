#!/usr/bin/env bash
#
# Regression tests for the skill's scripts. Run from anywhere:
#   bash tests/run.sh
# Needs rg, git and python3 - the same tools the skill needs.
#
# Fixture trees live in tests/fixtures/. Anything that needs .git directories
# (nested repositories, permalinks) is built in a temp dir at run time.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(dirname -- "$HERE")"
S="$SKILL/scripts"
FX="$HERE/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }
expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $2"$'\n'"actual:   $3"; fi
}
summary() { sed -n '/== HIT SUMMARY ==/,/TOTAL/p' | sed '1d'; }
gitc() { git -c user.name=test -c user.email=test@example.com "$@"; }

# ------------------------------------------------------------------ scan.sh
out="$(cd "$FX" && bash "$S/scan.sh" scan)"
expect_eq "scan: hit summary (exclusions and collision guards hold)" \
"     4  Stripe
     2  AWS
     1  Google Cloud
     2  OpenAI
     3  Vercel AI Gateway
     5  AI/ML hosted services (beyond the big-5 LLM vendors)
     1  Web platform services (captcha, analytics tags, widgets)
     1  Commercial-license libraries (not services)
    19  TOTAL hits across 8 vendor groups" "$(printf '%s\n' "$out" | summary)"

for path in vendor/ dist/ locales/ README.md web/ui/modal.js pnpm-lock.yaml \
            "provider.ts:7:" "provider.ts:8:"; do
  if printf '%s\n' "$out" | grep -q "scan/$path"; then
    bad "scan: nothing reported from $path"
  else
    ok "scan: nothing reported from $path"
  fi
done

expect_eq "scan: Ruby and Rust shapes are matched" "3" \
  "$(printf '%s\n' "$out" | grep -cE 'billing\.rb:(1|5):|lib\.rs:1:')"

expect_eq "scan: URL HOSTS lists hardcoded hosts, minus localhost" \
"      1 api.rss2json.com
      1 eu.api.smith.langchain.com" \
  "$(printf '%s\n' "$out" | sed -n '/== URL HOSTS/,/^#/p' | grep -v '^[=#]')"

# Env templates are dotfiles: scanned on purpose. A real .env (secrets) and
# hidden directories stay out.
expect_eq "scan: env templates are scanned" "2" \
  "$(printf '%s\n' "$out" | grep -c '^scan/\.env\.example:')"
expect_eq "scan: .env and hidden directories are not scanned" "0" \
  "$(printf '%s\n' "$out" | grep -cE '^scan/(\.env:|\.cache/)')"

# LangChain's hosted services match; the open langchain_core and langgraph
# libraries do not.
expect_eq "scan: LangSmith and LangGraph Platform, not the open libraries" \
"scan/app/tracing.py:1
scan/app/tracing.py:2" \
  "$(printf '%s\n' "$out" | grep -o '^scan/app/tracing\.py:[0-9]*')"

out2="$(cd "$FX" && bash "$S/scan.sh" scan)"
expect_eq "scan: output is identical across runs" "$out" "$out2"

expect_eq "scan --extra: residual group is added to the summary" \
  "     1  Handsontable (residual)" \
  "$(cd "$FX" && bash "$S/scan.sh" --extra extra.tsv scan | summary | grep Handsontable)"

: > "$TMP/empty.tsv"
expect_eq "scan --extra: an empty residual file changes nothing" \
  "$(printf '%s\n' "$out" | summary)" "$(cd "$FX" && bash "$S/scan.sh" --extra "$TMP/empty.tsv" scan | summary)"

bash "$S/scan.sh" --extra "$TMP/missing.tsv" "$FX/scan" >/dev/null 2>&1
expect_eq "scan --extra: missing file exits 2" "2" "$?"

PIA_PATTERNS="$TMP/missing.tsv" bash "$S/scan.sh" "$FX/scan" >/dev/null 2>&1
expect_eq "scan: missing pattern table exits 2" "2" "$?"

# Groups and alternations added from the DPG corpus (scripts/dpg_corpus.py):
# one real declaration or call per addition, plus every false positive the
# corpus showed before the patterns were tightened.
dout="$(bash "$S/scan.sh" "$FX/scan-dpg")"
expect_eq "scan: DPG-corpus additions hit their groups" \
"     1  Google Maps
     2  MongoDB
     1  AWS
     3  Microsoft 365 / Graph APIs
     1  Google Cloud
     1  Product analytics
     1  Observability (Datadog/New Relic)
     1  OpenAI
     1  Vendor API endpoints (raw HTTP)
     1  Realtime messaging SaaS (Pusher/PubNub/Ably)
     5  Data, search, feature-flag and CMS SaaS
     1  Support / CRM SaaS
     2  Payments (non-Stripe)
     1  E-signature and identity verification SaaS
     1  SMS and chat messaging SaaS
     6  AI/ML hosted services (beyond the big-5 LLM vendors)
     3  Geospatial SaaS
     2  Web platform services (captcha, analytics tags, widgets)
     4  Commercial-license libraries (not services)
    38  TOTAL hits across 19 vendor groups" "$(printf '%s\n' "$dout" | summary)"
expect_eq "scan: corpus false positives (clearBit, com.squareup, Matrix pushers, ESRI Shapefile, word lists, prose, embeds) stay quiet" "0" \
  "$(printf '%s\n' "$dout" | grep -c 'scan-dpg/negatives/')"

np="$(bash "$S/scan.sh" --print-patterns | grep -c '^rg -in ')"
nt="$(grep -cvE '^(#|$)' "$SKILL/references/patterns.tsv")"
expect_eq "scan --print-patterns: one line per pattern group" "$nt" "$np"

while IFS=$'\t' read -r label pat _; do
  case "$label" in ''|'#'*) continue ;; esac
  echo x | rg -i -e "$pat" >/dev/null 2>&1
  [ $? -eq 2 ] && bad "patterns.tsv: '$label' does not compile"
done < "$SKILL/references/patterns.tsv"
ok "patterns.tsv: every pattern compiles"

# ------------------------------------------------------------- manifests.sh
mkdir -p "$TMP/container/a" "$TMP/container/b"
git init -q "$TMP/container/a"; git init -q "$TMP/container/b"
bash "$S/manifests.sh" "$TMP/container" >/dev/null 2>&1
expect_eq "manifests: a directory of repositories exits 2" "2" "$?"

bash "$S/manifests.sh" "$TMP/container/a" >/dev/null 2>&1
expect_eq "manifests: a single repository exits 0" "0" "$?"

# --------------------------------------------------------------- linkify.py
R="$TMP/repo"
mkdir -p "$R/src"
printf 'line one\n\nline three\nline four\n' > "$R/a.py"
printf 'x = 1\ny = 2\n' > "$R/src/b.py"
cat > "$R/R.md" <<'EOF'
# Report

## Findings

### [PDA-001] [High] [CONFIRMED] Example
Claimed role: domain
Locations:
- `a.py:1` call, and `a.py:3-4` and `src/b.py:2`
- see [`docs`](https://example.com/keep)

---

## File Index

| `src/b.py:1` | x |

```
`a.py:1` inside a fence
```
EOF
git init -q "$R"; gitc -C "$R" add .; gitc -C "$R" commit -qm init
git -C "$R" remote add origin git@github.com:acme/demo.git
L=(python3 "$S/linkify.py" -q --allow-dirty)

"${L[@]}" "$R/R.md" >/dev/null
expect_eq "linkify: valid references pass the dry run" "0" "$?"

printf '`a.py:2` is blank\n' > "$R/blank.md"
"${L[@]}" "$R/blank.md" >/dev/null 2>&1
expect_eq "linkify: a reference to a blank line fails" "1" "$?"

printf '`a.py:9` is past the end\n' > "$R/range.md"
"${L[@]}" "$R/range.md" >/dev/null 2>&1
expect_eq "linkify: an out-of-range reference fails" "1" "$?"

cp "$R/R.md" "$R/inline.md"; cp "$R/R.md" "$R/foot.md"
"${L[@]}" --write "$R/inline.md"
expect_eq "linkify: inline mode links 4 references" "4" "$(grep -o '](https://github.com/acme/demo/blob/' "$R/inline.md" | wc -l | tr -d ' ')"
cp "$R/inline.md" "$R/inline2.md"; "${L[@]}" --write "$R/inline2.md"
cmp -s "$R/inline.md" "$R/inline2.md" && ok "linkify: inline re-run is a no-op" || bad "linkify: inline re-run is a no-op"

"${L[@]}" --write --footnotes "$R/foot.md"
expect_eq "linkify --footnotes: 4 numbered references" "[1] [2] [3] [4]" \
  "$(grep -oE '^\[[0-9]+\] https://github' "$R/foot.md" | sed 's/ https.*//' | tr '\n' ' ' | sed 's/ $//')"
grep -q '^\[1\] .*a.py#L1$' "$R/foot.md" && grep -q '`a.py:1` \[1\]' "$R/foot.md" \
  && ok "linkify --footnotes: marker and URL agree" || bad "linkify --footnotes: marker and URL agree"
grep -q '(https://example.com/keep)' "$R/foot.md" \
  && ok "linkify --footnotes: foreign links stay inline" || bad "linkify --footnotes: foreign links stay inline"
grep -q '^`a.py:1` inside a fence$' "$R/foot.md" \
  && ok "linkify --footnotes: fenced code untouched" || bad "linkify --footnotes: fenced code untouched"
awk '/^\[1\] /{f=NR} /^---$/{r=NR} END{exit !(f && r && f < r)}' "$R/foot.md" \
  && ok "linkify --footnotes: list sits before the section's --- rule" \
  || bad "linkify --footnotes: list sits before the section's --- rule"
for mode in "" "--footnotes"; do
  cp "$R/foot.md" "$R/foot2.md"; "${L[@]}" --write $mode "$R/foot2.md"
  cmp -s "$R/foot.md" "$R/foot2.md" && ok "linkify: re-run ${mode:-without flag} on a footnoted report is a no-op" \
    || bad "linkify: re-run ${mode:-without flag} on a footnoted report is a no-op"
done
"${L[@]}" --write --footnotes "$R/inline2.md"
cmp -s "$R/foot.md" "$R/inline2.md" && ok "linkify: inline then --footnotes equals direct --footnotes" \
  || bad "linkify: inline then --footnotes equals direct --footnotes"

# Next.js route paths: groups, dynamic segments and spaces must be validated,
# linked, and percent-encoded so the Markdown link destination stays intact.
N="$TMP/next"
mkdir -p "$N/app/(auth)/[locale]/(form filler)/[[...slug]]"
printf 'export default 1\n' > "$N/app/(auth)/[locale]/(form filler)/[[...slug]]/page.tsx"
git init -q "$N"; gitc -C "$N" add .; gitc -C "$N" commit -qm init
git -C "$N" remote add origin git@github.com:acme/demo.git
printf -- '- `app/(auth)/[locale]/(form filler)/[[...slug]]/page.tsx:1` call\n' > "$N/R.md"
printf -- '- `app/(auth)/[locale]/(form filler)/[[...slug]]/page.tsx:2` past the end\n' > "$N/range.md"
"${L[@]}" "$N/range.md" >/dev/null 2>&1
expect_eq "linkify: an out-of-range Next.js route reference fails" "1" "$?"
"${L[@]}" --write "$N/R.md"
grep -qF '](https://github.com/acme/demo/blob/'"$(git -C "$N" rev-parse HEAD)"'/app/%28auth%29/%5Blocale%5D/%28form%20filler%29/%5B%5B...slug%5D%5D/page.tsx#L1)' "$N/R.md" \
  && ok "linkify: Next.js route path is linked and percent-encoded" \
  || bad "linkify: Next.js route path is linked and percent-encoded" "$(cat "$N/R.md")"
cp "$N/R.md" "$N/R2.md"; "${L[@]}" --write "$N/R2.md"
cmp -s "$N/R.md" "$N/R2.md" && ok "linkify: re-run on a Next.js route link is a no-op" \
  || bad "linkify: re-run on a Next.js route link is a no-op"

# ----------------------------------------------------------------- report.py
RP=(python3 "$S/report.py")
for f in draft verified final; do
  "${RP[@]}" check "$FX/reports/$f.md" >/dev/null
  expect_eq "report check: $f.md is clean" "0" "$?"
done

msgs="$("${RP[@]}" check "$FX/reports/broken.md")"
expect_eq "report check: broken.md fails" "1" "$?"
for want in "malformed finding heading" "duplicates the ID" "ADJUSTED needs a reason" \
            "still has a \`?\` severity" "REJECTED and \[N/A\] go together" \
            "missing \`Claimed role:\`" "does not match the headings"; do
  printf '%s\n' "$msgs" | grep -q "$want" && ok "report check: catches '$want'" \
    || bad "report check: catches '$want'"
done

{ cat "$FX/reports/final.md"; printf 'See `src/domain/order.ts:2` and `:5`.\n'; } > "$TMP/bare.md"
msgs="$("${RP[@]}" check "$TMP/bare.md")"
printf '%s\n' "$msgs" | grep -q 'bare reference `:5`' \
  && ok "report check: catches a bare :NN continuation" || bad "report check: catches a bare :NN continuation"

{ cat "$FX/reports/final.md"; printf 'An em dash \342\200\224 here\n'; } > "$TMP/nonascii.md"
msgs="$("${RP[@]}" check "$TMP/nonascii.md")"
printf '%s\n' "$msgs" | grep -q 'non-ASCII' \
  && ok "report check: catches non-ASCII" || bad "report check: catches non-ASCII"

sed 's/^- Verification: pending/- Verification: completed 2026-10-29/' "$FX/reports/draft.md" > "$TMP/early.md"
msgs="$("${RP[@]}" check "$TMP/early.md")"
printf '%s\n' "$msgs" | grep -q 'still UNVERIFIED in a completed report' \
  && ok "report check: completed report with UNVERIFIED findings fails" \
  || bad "report check: completed report with UNVERIFIED findings fails"

cp "$FX/reports/draft.md" "$TMP/d.md"
"${RP[@]}" finalize "$TMP/d.md" >/dev/null 2>&1
expect_eq "report finalize: refuses while findings are UNVERIFIED" "1" "$?"

cp "$FX/reports/verified.md" "$TMP/v.md"
"${RP[@]}" finalize --date 2026-10-29 "$TMP/v.md" >/dev/null
expect_eq "report finalize: succeeds on a verified report" "0" "$?"
grep -q '^| Critical | 1 |$' "$TMP/v.md" && grep -q '^| Medium | 1 |$' "$TMP/v.md" \
  && ok "report finalize: table counts the final headings" || bad "report finalize: table counts the final headings"
grep -q '^- Verification: completed 2026-10-29$' "$TMP/v.md" \
  && ok "report finalize: header marked completed" || bad "report finalize: header marked completed"
msgs="$("${RP[@]}" check "$TMP/v.md")"
left="$(printf '%s\n' "$msgs" | grep -c 'placeholder left')"
expect_eq "report check: exec summary and file index still to write after finalize" "2" "$left"
cp "$TMP/v.md" "$TMP/v2.md"; "${RP[@]}" finalize --date 2026-10-29 "$TMP/v2.md" >/dev/null
cmp -s "$TMP/v.md" "$TMP/v2.md" && ok "report finalize: re-run is a no-op" || bad "report finalize: re-run is a no-op"

# ------------------------------------------------------------ dpg_corpus.py
DC=(python3 -I "$S/dpg_corpus.py")
C="$TMP/corpus"
"${DC[@]}" fetch "$C" --limit 3 --from-file "$FX/dpg/api.json" >/dev/null
expect_eq "dpg fetch: category filter, newest first, limit" \
  "GID0000004 GID0000003 GID0000005" \
  "$(python3 -c 'import json,sys; print(*[d["dpgId"] for d in json.load(open(sys.argv[1]))])' "$C/dpgs.json")"
expect_eq "dpg fetch: comma list and JSON blob split, duplicates dropped, nothing expanded" \
"GID0000004 https://github.com/blob/app
GID0000004 https://github.com/blob/admin
GID0000004 https://github.com/other/admin
GID0000004 https://github.com/blob/api
GID0000003 https://github.com/acme/core
GID0000003 https://github.com/acme/cli
GID0000003 https://github.com/acme/web
GID0000005 https://github.com/someorg
GID0000005 https://docs.example.org/x" "$(sed 1d "$C/sources.tsv" | cut -f1,4 | tr '\t' ' ')"

# clone, offline: one source already cloned, one that is not a git repository
printf 'dpgId\tname\tfield\turl\nG1\tx\tsourceURL\thttps://example.com/acme/repo\nG1\tx\totherSources\thttp://127.0.0.1:9/org\n' \
  > "$C/sources.tsv"
mkdir -p "$C/G1/acme__repo" && gitc -C "$C/G1/acme__repo" init -q \
  && gitc -C "$C/G1/acme__repo" commit -q --allow-empty -m init
"${DC[@]}" clone "$C" >/dev/null 2>&1
expect_eq "dpg clone: existing clone kept, non-repo URL skipped and logged" \
  "exists not-a-repo" "$(sed 1d "$C/clone-log.tsv" | cut -f4 | tr '\n' ' ' | sed 's/ $//')"

# inventory: the fixture repo holds one manifest of every supported kind
rm -rf "$C/G1/acme__repo" && cp -r "$FX/dpg/repo" "$C/G1/acme__repo"
printf '[{"dpgId": "G1", "name": "x", "dpgSince": "2026-01-01"}]\n' > "$C/dpgs.json"
inv="$("${DC[@]}" inventory "$C" 2>/dev/null)"
expect_eq "dpg inventory: direct deps of every manifest kind, node_modules pruned" \
  "$(cat "$FX/dpg/expected-deps.tsv")" "$(sed 1d "$C/deps.tsv" | cut -f3,4)"
printf '%s\n' "$inv" | grep -q '20 of 21 manifests parsed (1 errors)' \
  && ok "dpg inventory: an unparseable manifest is counted, not skipped" \
  || bad "dpg inventory: an unparseable manifest is counted, not skipped" "$inv"
grep -q '^G1	acme__repo	bad/package.json	JSONDecodeError' "$C/inventory-errors.tsv" \
  && ok "dpg inventory: the parse error is logged" || bad "dpg inventory: the parse error is logged"

# coverage: declaration lines tested against a pattern table, like scan.sh does
printf 'Test Firebase\t"firebase"\t\nTest Leaflet\tleaflet\t\nTest Firebase SDK\tcom\\.google\\.firebase\t\nTest AWS\tcom\\.amazonaws\t\nTest Sentry\tsentry\t\n' \
  > "$TMP/cov.tsv"
printf 'ecosystem\tdependency\tdpgs\tverdict\nnpm\tfirebase\t1\tproprietary\npypi\ttwilio\t1\tproprietary\nnpm\tnot-declared\t1\tproprietary\nmaven\tcom.amazonaws:aws-java-sdk-s3\t1\tproprietary\nmaven\tcom.google.firebase:firebase-auth\t1\tproprietary\n' \
  > "$C/proprietary.tsv"
"${DC[@]}" coverage "$C" --patterns "$TMP/cov.tsv" >/dev/null
expect_eq "dpg coverage: caught, gap and undeclared proprietary deps" \
"maven com.amazonaws:aws-java-sdk-s3 caught Test AWS
maven com.google.firebase:firebase-auth caught Test Firebase SDK
npm firebase caught Test Firebase
pypi twilio gap
npm not-declared not-in-deps" "$(sed 1d "$C/coverage.tsv" | cut -f1,2,7,8 | tr '\t' ' ' | sed 's/ *$//')"
# okhttp/junit sit on the lines next to the Firebase and AWS declarations, and
# django appears as an extra of sentry-sdk: none of that is a declaration
expect_eq "dpg coverage: only real matches are reported, never a neighbouring line or an extra" \
"gradle-plugin com.google.firebase.crashlytics Test Firebase SDK
maven com.google.firebase:firebase-bom Test Firebase SDK
npm leaflet Test Leaflet
pypi sentry-sdk Test Sentry" "$(sed 1d "$C/coverage-other.tsv" | cut -f1,2,4 | tr '\t' ' ')"

# --------------------------------------------------------------- plain ASCII
nonascii="$(cd "$SKILL" && rg -l '[^\x00-\x7F]' --glob '!tasks/**' . 2>/dev/null)"
expect_eq "every shipped file is plain ASCII" "" "$nonascii"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
