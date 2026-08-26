#!/usr/bin/env bash
#
# scan.sh - deterministic vendor-SDK scan for the platform-independence-analyzer
# skill (Tier 1). Prints grouped `file:line:match` hits, one group per vendor,
# so the Tier 1 draft is a rendering of reproducible output instead of freehand
# grepping.
#
# Requires: ripgrep (rg) only.
#
# Language coverage: JS/TS (incl. React Native), Python, Java/Kotlin, Go,
# .NET/C#, Swift/Objective-C, and CocoaPods/Gradle manifests. Ruby, PHP, Rust,
# and Dart/Flutter import shapes are NOT covered - no output for those
# ecosystems means nothing was searched for, not that the repo is clean.
# See SKILL.md Step 3.
#
# Every pattern runs under `rg -in`, so case carries no signal: `import firebase`
# matches Swift `import FirebaseCore`, Python `import firebase_admin`, and JS
# `import firebase from` alike. Do not write patterns that depend on case.
# Usage:    scripts/scan.sh [ROOT_DIR]      (ROOT_DIR defaults to ".")
#
# Output shape: a per-vendor HIT SUMMARY first, then the grouped detail. Compare
# the summary counts against the detail you actually received - if they disagree,
# the output was truncated somewhere downstream and the draft would be silently
# incomplete. Redirect to a file and read that rather than piping to a tool with
# an output cap.
#
# Exit codes: 0 = ran (with or without hits); 127 = ripgrep not installed.
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

ROOT="${1:-.}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required but was not found on PATH" >&2
  echo "install it (pacman -S ripgrep / apt install ripgrep / brew install ripgrep), then re-run" >&2
  exit 127
fi

EXCLUDES=(
  --glob '!**/vendor/**'
  --glob '!**/Pods/**'          # CocoaPods deps, committed in some iOS/RN repos
  --glob '!**/*.pbxproj'        # generated Xcode project; mirrors the Podfile
  --glob '!**/.expo/**'         # generated Expo cache
  --glob '!**/*.lock'
  --glob '!**/package-lock.json'
  --glob '!**/*.md'
  --glob '!**/PLATFORM-DEPENDENCY-ANALYSIS.*'
)

# Parallel arrays: LABELS[i] is the vendor name, PATTERNS[i] its rg regex.
# Patterns mirror references/dependency-patterns.md (case-insensitive via -i,
# word boundaries to cut substring/prose noise).
LABELS=(
  "Firebase"
  "React Native / mobile vendor SDKs (attribute to the underlying service - classification-rules R4)"
  "Google Maps"
  "Stripe"
  "MongoDB"
  "Twilio / SendGrid"
  "AWS (non-S3 - filter S3-only per classification-rules R4)"
  "Azure"
  "Google Cloud"
  "Algolia"
  "Auth0 / Okta"
  "Analytics (Segment/Mixpanel/Amplitude/PostHog)"
  "Observability (Datadog/New Relic)"
  "OpenAI (check for base_url override - classification-rules R4/R5)"
  "Anthropic"
  "Google Gemini"
  "Cohere"
  "Mistral"
  "LLM wrapper SDKs (attribute to the underlying vendor - classification-rules R4)"
  "Vendor API endpoints, raw HTTP (deliberately noisy - Tier 2 prunes)"
)
PATTERNS=(
  "@react-native-firebase|from ['\"]firebase|require\\(['\"]firebase|firebase[-_](admin|functions)|\\bimport firebase|@angular/fire|\\b(reactfire|vuefire)\\b|react-firebase-hooks|firestore\\(|getFirestore|\\bgetAuth\\(|onAuthStateChanged|createUserWithEmailAndPassword|signInWith(EmailAndPassword|Credential|CustomToken|Popup|Redirect|PhoneNumber)\\(|onSnapshot\\(|firebase\\.google\\.com/go|com\\.google\\.firebase|com\\.google\\.gms\\.google-services|GoogleService-Info|\\bFirebase(Admin|App|Core|Firestore|Auth|Storage|Messaging|Analytics|Crashlytics|RemoteConfig)\\b|pod ['\"]Firebase"
  "@react-native-firebase/|react-native-purchases|\\brevenuecat\\b|react-native-onesignal|\\bonesignal\\b|react-native-google-mobile-ads|react-native-fbsdk|@react-native-google-signin|@stripe/stripe-react-native|react-native-maps|@sentry/react-native|@bugsnag/react-native|react-native-branch|\\bappsflyer\\b|react-native-adjust|@intercom/intercom-react-native|react-native-zendesk|react-native-code-push|\\bappcenter-|react-native-iap|expo-in-app-purchases|@segment/analytics-react-native|@amplitude/analytics-react-native|mixpanel-react-native|posthog-react-native|@react-native-community/push-notification-ios"
  "@googlemaps|google\\.maps|googlemaps\\.Client|new google\\.|googlemaps\\.github\\.io/maps|\\bimport GoogleMaps\\b|pod ['\"]GoogleMaps|com\\.google\\.android\\.gms\\.maps"
  "from ['\"]stripe['\"]|require\\(['\"]stripe|import Stripe|\\bstripe\\.[a-zA-Z]|stripe/stripe-go|using Stripe\\b|\\bStripeConfiguration\\b|com\\.stripe\\.android"
  "\\bMongoClient\\b|require\\(['\"](mongodb|mongoose)|\\bmongoose\\b|\\bpymongo\\b|com\\.mongodb|go\\.mongodb\\.org|mongo-driver|MongoDB\\.Driver"
  "\\btwilio\\b|require\\(['\"](twilio|@sendgrid)|@sendgrid|\\bsendgrid\\b"
  "aws-sdk|\\bboto3\\b|@aws-sdk|aws-amplify|@aws-amplify/|com\\.amazonaws|software\\.amazon\\.awssdk|\\bAWSSDK\\b|using Amazon\\."
  "@azure/|azure\\.identity|azure\\.storage|azure-sdk-for-go|using Azure\\.|Microsoft\\.Azure\\."
  "@google-cloud/|google\\.cloud\\.|cloud\\.google\\.com/go"
  "algoliasearch|@algolia/"
  "\\bauth0\\b|@auth0/|@okta/|okta-auth"
  "segment\\.io|\\bmixpanel\\b|\\bamplitude\\.|\\bposthog\\b"
  "\\bdatadog\\b|dd-trace|\\bnewrelic\\b|@datadog/"
  "from ['\"]?openai\\b|require\\(['\"]openai|\\bimport openai\\b|\\bOpenAI\\(|\\bAzureOpenAI\\(|\\bopenai\\.[a-zA-Z]"
  "@anthropic-ai/|from ['\"]?anthropic\\b|\\bimport anthropic\\b|\\bAnthropic\\(|AnthropicBedrock|AnthropicVertex|\\banthropic\\.[a-zA-Z]"
  "@google/generative-ai|@google/genai|google-genai|google[-.]generativeai|google import genai|\\bGoogleGenerativeAI\\b|\\bgenai\\.[a-zA-Z]"
  "cohere-ai|from ['\"]?cohere\\b|\\bimport cohere\\b|\\bCohereClient\\b|\\bcohere\\.[a-zA-Z]"
  "@mistralai/|from ['\"]?mistralai\\b|\\bimport mistralai\\b|\\bMistralClient\\b|\\bMistral\\(|\\bmistralai\\.[a-zA-Z]"
  "langchain[_.-](openai|anthropic|google_genai|google-genai|google_vertexai|cohere|mistralai|aws)|@langchain/(openai|anthropic|google-genai|google-vertexai|cohere|mistralai|aws)|@ai-sdk/(openai|anthropic|google|mistral|cohere|amazon-bedrock)|llama[_-]index\\.llms\\.[a-z]|\\bChat(OpenAI|Anthropic|GoogleGenerativeAI|VertexAI|Bedrock|Cohere|MistralAI)\\b|\\bAzureChatOpenAI\\b|\\blitellm\\b"
  "api\\.(stripe|openai|anthropic|twilio|sendgrid|cohere|mistral|mixpanel|amplitude|segment|contentful|pinecone|notion|airtable)\\.(com|io|ai)|api\\.datadoghq\\.com|\\.googleapis\\.com|\\.firebaseio\\.com|hooks\\.slack\\.com|\\.openai\\.azure\\.com|\\.algolia(net)?\\.(com|net)|ingest\\.sentry\\.io|\\.snowflakecomputing\\.com|app\\.launchdarkly\\.com"
)

echo "# platform-independence scan"
echo "# root: $ROOT"
echo

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
  for i in "${!LABELS[@]}"; do
    [ -n "${RESULTS[$i]:-}" ] && printf '== %s ==\n%s\n\n' "${LABELS[$i]}" "${RESULTS[$i]}"
  done
fi

if [ "$found_any" -eq 0 ]; then
  echo "No proprietary vendor SDK usage matched. Repo may be clean; still emit the report."
fi
