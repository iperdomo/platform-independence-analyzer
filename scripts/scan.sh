#!/usr/bin/env bash
#
# scan.sh - deterministic vendor-SDK scan for the platform-independence-analyzer
# skill (Tier 1). Prints grouped `file:line:match` hits, one group per vendor,
# so the Tier 1 draft is a rendering of reproducible output instead of freehand
# grepping.
#
# Requires: ripgrep (rg) only.
# Usage:    scripts/scan.sh [ROOT_DIR]      (ROOT_DIR defaults to ".")
#
# Exit codes: 0 = ran (with or without hits); 127 = ripgrep not installed.
#
# ripgrep respects .gitignore by default, so node_modules/dist/build/.venv/
# target/.next/coverage are already skipped when gitignored. The --glob
# exclusions below cover cases rg will not skip on its own (committed vendor/
# dirs, lock files, and Markdown docs that mention vendor names in prose).

set -uo pipefail

ROOT="${1:-.}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required but was not found on PATH" >&2
  exit 127
fi

EXCLUDES=(
  --glob '!**/vendor/**'
  --glob '!**/*.lock'
  --glob '!**/package-lock.json'
  --glob '!**/*.md'
)

# Parallel arrays: LABELS[i] is the vendor name, PATTERNS[i] its rg regex.
# Patterns mirror references/dependency-patterns.md (case-insensitive via -i,
# word boundaries to cut substring/prose noise).
LABELS=(
  "Firebase"
  "Google Maps"
  "Stripe"
  "MongoDB"
  "Twilio / SendGrid"
  "AWS (non-S3 - filter S3-only in Step 6)"
  "Azure"
  "Google Cloud"
  "Algolia"
  "Auth0 / Okta"
  "Analytics (Segment/Mixpanel/Amplitude/PostHog)"
  "Observability (Datadog/New Relic)"
  "OpenAI (check for base_url override - see Step 6)"
  "Anthropic"
  "Google Gemini"
  "Cohere"
  "Mistral"
)
PATTERNS=(
  "from ['\"]firebase|firebase-admin|firestore\\(|getFirestore"
  "@googlemaps|google\\.maps|googlemaps\\.Client|new google\\."
  "from ['\"]stripe['\"]|import Stripe|\\bstripe\\.[a-zA-Z]"
  "\\bMongoClient\\b|\\bmongoose\\b|\\bpymongo\\b|com\\.mongodb"
  "\\btwilio\\b|@sendgrid|\\bsendgrid\\.[a-zA-Z]"
  "aws-sdk|\\bboto3\\b|@aws-sdk"
  "@azure/|azure\\.identity|azure\\.storage"
  "@google-cloud/|google\\.cloud\\."
  "algoliasearch|@algolia/"
  "\\bauth0\\b|@auth0/|@okta/|okta-auth"
  "segment\\.io|\\bmixpanel\\b|\\bamplitude\\.|\\bposthog\\b"
  "\\bdatadog\\b|dd-trace|\\bnewrelic\\b|@datadog/"
  "from ['\"]?openai\\b|require\\(['\"]openai|\\bimport openai\\b|\\bOpenAI\\(|\\bAzureOpenAI\\(|\\bopenai\\.[a-zA-Z]"
  "@anthropic-ai/|from ['\"]?anthropic\\b|\\bimport anthropic\\b|\\bAnthropic\\(|AnthropicBedrock|AnthropicVertex|\\banthropic\\.[a-zA-Z]"
  "@google/generative-ai|@google/genai|google-genai|google[-.]generativeai|google import genai|\\bGoogleGenerativeAI\\b|\\bgenai\\.[a-zA-Z]"
  "cohere-ai|from ['\"]?cohere\\b|\\bimport cohere\\b|\\bCohereClient\\b|\\bcohere\\.[a-zA-Z]"
  "@mistralai/|from ['\"]?mistralai\\b|\\bimport mistralai\\b|\\bMistralClient\\b|\\bMistral\\(|\\bmistralai\\.[a-zA-Z]"
)

echo "# platform-independence scan"
echo "# root: $ROOT"
echo

found_any=0
for i in "${!LABELS[@]}"; do
  label="${LABELS[$i]}"
  pat="${PATTERNS[$i]}"

  out="$(rg -in --no-heading --color=never "${EXCLUDES[@]}" -e "$pat" -- "$ROOT")"
  rc=$?

  case "$rc" in
    0)
      found_any=1
      printf '== %s ==\n%s\n\n' "$label" "$out"
      ;;
    1)
      : # no matches for this vendor
      ;;
    *)
      printf 'warning: ripgrep failed (exit %d) for %s\n' "$rc" "$label" >&2
      ;;
  esac
done

if [ "$found_any" -eq 0 ]; then
  echo "No proprietary vendor SDK usage matched. Repo may be clean; still emit the report."
fi
