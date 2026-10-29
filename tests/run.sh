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
     2  OpenAI
     3  Vercel AI Gateway
     1  AI/ML hosted services (beyond the big-5 LLM vendors)
     1  Web platform services (captcha, analytics tags, widgets)
    13  TOTAL hits across 6 vendor groups" "$(printf '%s\n' "$out" | summary)"

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

expect_eq "scan: URL HOSTS lists hardcoded hosts, minus localhost" "      1 api.rss2json.com" \
  "$(printf '%s\n' "$out" | sed -n '/== URL HOSTS/,/^#/p' | grep -v '^[=#]')"

out2="$(cd "$FX" && bash "$S/scan.sh" scan)"
expect_eq "scan: output is identical across runs" "$out" "$out2"

expect_eq "scan --extra: residual group is added to the summary" \
  "     1  Highcharts (residual)" \
  "$(cd "$FX" && bash "$S/scan.sh" --extra extra.tsv scan | summary | grep Highcharts)"

: > "$TMP/empty.tsv"
expect_eq "scan --extra: an empty residual file changes nothing" \
  "$(printf '%s\n' "$out" | summary)" "$(cd "$FX" && bash "$S/scan.sh" --extra "$TMP/empty.tsv" scan | summary)"

bash "$S/scan.sh" --extra "$TMP/missing.tsv" "$FX/scan" >/dev/null 2>&1
expect_eq "scan --extra: missing file exits 2" "2" "$?"

PIA_PATTERNS="$TMP/missing.tsv" bash "$S/scan.sh" "$FX/scan" >/dev/null 2>&1
expect_eq "scan: missing pattern table exits 2" "2" "$?"

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

# --------------------------------------------------------------- plain ASCII
nonascii="$(cd "$SKILL" && rg -l '[^\x00-\x7F]' --glob '!tasks/**' . 2>/dev/null)"
expect_eq "every shipped file is plain ASCII" "" "$nonascii"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
