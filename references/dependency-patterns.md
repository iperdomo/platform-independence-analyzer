# Dependency Patterns Reference

## Import Pattern Detection

### JavaScript/TypeScript
```javascript
// Direct imports - VIOLATION
import firebase from 'firebase/app';
import { GoogleMapsAPI } from '@googlemaps/js-api-loader';
const stripe = require('stripe')('sk_test_...');

// Abstracted imports - GOOD
import { PaymentService } from './services/payment.service';
import { MapsProvider } from './providers/maps.provider';
```

### Python
```python
# Direct imports - VIOLATION
import firebase_admin
from googlemaps import Client
import stripe

# Abstracted imports - GOOD
from services.payment_service import PaymentService
from providers.maps_provider import MapsProvider
```

### Java
```java
// Direct imports - VIOLATION
import com.google.firebase.*;
import com.stripe.Stripe;
import com.mongodb.MongoClient;

// Abstracted imports - GOOD
import com.company.services.PaymentService;
import com.company.providers.DatabaseProvider;
```

### Go

Module paths, not bare package names — this is why the JS/Python patterns miss
Go entirely (`go.mongodb.org/mongo-driver` shares no substring with `mongoose`
or `pymongo`).

```go
// Direct imports - VIOLATION
import (
	"github.com/stripe/stripe-go/v76"
	"go.mongodb.org/mongo-driver/mongo"
	"cloud.google.com/go/storage"
	firebase "firebase.google.com/go/v4"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
)

// Abstracted - GOOD: domain depends on an interface declared in the consuming package
type PaymentGateway interface { Charge(ctx context.Context, c Charge) error }
```

### .NET / C#

`using` namespaces, PascalCase.

```csharp
// Direct imports - VIOLATION
using Stripe;
using MongoDB.Driver;
using Azure.Identity;
using Google.Cloud.Storage.V1;
using Amazon.DynamoDBv2;
using FirebaseAdmin;

// Abstracted - GOOD
using Company.Application.Ports;   // IPaymentGateway, injected via DI
```

### React Native / mobile

A React Native app is three codebases in one directory, and the JS half hides
the other two. `@react-native-firebase/*` shares no substring with `firebase/app`,
and the native projects declare the same vendors again in CocoaPods and Gradle —
so a repo can look Firebase-free in `src/` while `ios/Podfile` and
`android/app/build.gradle` wire it in.

```typescript
// Direct usage - VIOLATION (a Firebase finding, not a "react-native" finding)
import firestore from '@react-native-firebase/firestore';
import Purchases from 'react-native-purchases';   // RevenueCat
await firestore().collection('users').doc(id).get();

// Abstracted - GOOD
import { userRepository } from '../data/user.repository';
```

```swift
// ios/AppDelegate.swift - VIOLATION when domain code follows suit
import FirebaseCore
FirebaseApp.configure()
```

```ruby
# ios/Podfile and android/app/build.gradle - the native declarations
pod 'Firebase/Analytics'
pod 'GoogleMaps'
# apply plugin: 'com.google.gms.google-services'
```

React Native itself, the Expo SDK, and open modules like `react-native-mmkv` or
`@react-native-async-storage/async-storage` are MIT — never findings on their
own. See "Mobile Binding Attribution" below.

### Ruby / PHP / Rust / Dart — not pattern-covered

`scripts/scan.sh` has no patterns for these ecosystems. Their manifests
(`Gemfile`, `composer.json`, `Cargo.toml`, `pubspec.yaml`) are still read in
Step 1 and judged in Step 2, so the vendor names are known — Step 3 must grep
for them explicitly rather than trusting the scanner's silence. Typical shapes
to grep for:

- Ruby: `Stripe::`, `Twilio::REST`, `Mongoid`, `Google::Cloud`, `require "stripe"`
- PHP: `use Stripe\`, `use Twilio\`, `MongoDB\Client`, `Google\Cloud\`
- Rust: `stripe_rust`, `mongodb::`, `aws_sdk_`, `google_cloud_`
- Dart/Flutter: `package:firebase_core`, `package:cloud_firestore`,
  `package:firebase_auth`, `package:google_maps_flutter`, `package:stripe_*`

## API Call Patterns

### Firebase
```javascript
// Direct usage - VIOLATION
firebase.auth().createUser({...});
db.collection('users').add({...});

// Abstracted usage - GOOD
authService.createUser({...});
userRepository.add({...});
```

### Google Maps
```javascript
// Direct usage - VIOLATION
new google.maps.Map(element, options);
directionsService.route({...});

// Abstracted usage - GOOD
mapProvider.createMap(element, options);
mapProvider.calculateRoute({...});
```

### MongoDB
```javascript
// Direct usage - VIOLATION
const client = new MongoClient(uri);
db.collection('users').findOne({...});

// Abstracted usage - GOOD
const repository = container.get('UserRepository');
repository.findById(id);
```

## Configuration Patterns

Reading vendor configuration (API keys, project IDs, endpoints) from env vars
or a config file is **Acceptable** — it is not a violation on its own. Config
does not invoke the SDK, and every vendor needs some configuration regardless
of how well the code is abstracted. The lock-in question is whether *business
logic* calls the SDK, not whether config names a vendor.

```javascript
// Acceptable: config names a vendor but invokes nothing.
const firebaseConfig = {
  apiKey: process.env.FIREBASE_API_KEY,
  authDomain: process.env.FIREBASE_AUTH_DOMAIN,
  projectId: process.env.FIREBASE_PROJECT_ID
};
firebase.initializeApp(firebaseConfig); // classified by WHERE this runs
```

Classify such a site by the file's role (classification-rules R2): a call like
`initializeApp(...)` in a bootstrap/composition root is Acceptable; the same
call scattered through domain code is the violation — because of the direct
SDK use in domain code, not because the config mentions a vendor.

## Common Anti-Patterns

Vendor-lock-in shapes to flag (in scope for this skill):

1. **Scattered API calls**: vendor SDK calls throughout business logic.
2. **Direct SDK usage**: using vendor SDKs directly in domain code instead of
   through an adapter/port/repository.
3. **Vendor types in public interfaces**: an abstraction exists but leaks
   vendor types through its public surface.

Out of scope (do NOT flag — these are architectural-quality concerns, not
lock-in): general tight coupling, missing interfaces around open-source
libraries, or config that merely names a vendor. See classification-rules R1
for the full scope boundary.

## Detection Keywords

### High-Risk Keywords
- `firebase`, `firestore`, `firebase-admin`, `firebase_admin`,
  `firebase-functions`, `@react-native-firebase/*`, `@angular/fire`,
  `reactfire`, `vuefire`, `react-firebase-hooks`, `FirebaseCore` /
  `FirebaseFirestore` / `FirebaseAuth` (Swift), `pod 'Firebase/...'`,
  `com.google.gms.google-services` (Gradle), `GoogleService-Info` (iOS plist)
- `googleapis`, `google.maps`, `@googlemaps`
- `stripe`, `stripe.com`
- `twilio`, `sendgrid`, `@sendgrid`
- `mongodb`, `mongoose`, `MongoClient`, `pymongo`
- `aws-sdk`, `boto3`, `@aws-sdk` (filter S3-only out — see acceptable list)
- `azure-`, `@azure/`
- `@google-cloud/`, `google.cloud.`
- `algolia`, `@algolia/`
- `auth0`, `@auth0/`, `okta`, `@okta/`
- `segment`, `mixpanel`, `amplitude`, `posthog`
- `datadog`, `newrelic`, `dd-trace`, `@datadog/`
- `pusher`, `pubnub`, `ably`
- `mapbox`, `here-`, `@here/`
- `intercom`, `zendesk`, `salesforce`, `@salesforce/`
- React Native / mobile bindings (the module is the wrapper — name the service
  it binds to; see "Mobile Binding Attribution" below):
  - `@react-native-firebase/*` → Firebase
  - `react-native-purchases` → RevenueCat; `react-native-iap`,
    `expo-in-app-purchases` → App Store / Play Billing
  - `react-native-onesignal` → OneSignal; `@react-native-community/push-notification-ios` → APNs
  - `react-native-google-mobile-ads` → Google AdMob; `react-native-fbsdk-next` → Meta
  - `@react-native-google-signin/google-signin` → Google Identity
  - `@stripe/stripe-react-native` → Stripe; `react-native-maps` → Google/Apple Maps
  - `@sentry/react-native` → Sentry; `@bugsnag/react-native` → Bugsnag
  - `react-native-branch`, `appsflyer-react-native-plugin`, `react-native-adjust`
    → attribution SaaS (Branch, AppsFlyer, Adjust)
  - `@intercom/intercom-react-native`, `react-native-zendesk` → Intercom, Zendesk
  - `react-native-code-push`, `appcenter-*` → Microsoft App Center
  - `@segment/analytics-react-native`, `@amplitude/analytics-react-native`,
    `mixpanel-react-native`, `posthog-react-native` → the analytics vendor
  - `aws-amplify`, `@aws-amplify/*` → AWS (matches neither `aws-sdk` nor `@aws-sdk`)
- LLM/AI SaaS APIs (proprietary services behind permissively licensed SDKs —
  the service, not the client license, creates the lock-in):
  - `openai`, `OpenAI`, `AzureOpenAI` (see the base_url note under acceptable patterns)
  - `@anthropic-ai/sdk`, `anthropic`, `Anthropic`, `AnthropicBedrock`, `AnthropicVertex`
  - `@google/generative-ai`, `@google/genai`, `google-generativeai`, `google-genai`, `genai`
  - `cohere-ai`, `cohere`, `CohereClient`
  - `@mistralai/mistralai`, `mistralai`, `MistralClient`
  - OpenAI-compatible providers (Groq, Together, Perplexity, Fireworks, ...) are
    usually reached via the OpenAI SDK with a `base_url` — they surface under the
    `openai` sweep, then the endpoint check decides lock-in.
  - LLM wrapper SDKs (the vendor SDK is a transitive dependency, so the direct
    vendor patterns above miss them entirely): `langchain_openai`,
    `langchain_anthropic`, `@langchain/openai`, `@langchain/anthropic`,
    `@ai-sdk/openai`, `@ai-sdk/anthropic`, `llama_index.llms.*`, `ChatOpenAI`,
    `ChatAnthropic`, `ChatGoogleGenerativeAI`, `AzureChatOpenAI`, `litellm`.
    See "LLM Wrapper Attribution" below and classification-rules R4.
- Raw HTTP calls to vendor endpoints (no SDK involved, so every SDK pattern
  misses them): `api.stripe.com`, `api.openai.com`, `api.anthropic.com`,
  `api.twilio.com`, `api.sendgrid.com`, `*.googleapis.com`, `*.firebaseio.com`,
  `hooks.slack.com`, `*.openai.azure.com`, `api.datadoghq.com`,
  `api.pinecone.io`, `ingest.sentry.io`, `*.snowflakecomputing.com`.

## LLM Wrapper Attribution

LangChain, LlamaIndex, the Vercel AI SDK, and LiteLLM are themselves MIT- or
Apache-licensed. **The wrapper is never the finding** — attribute it to the
proprietary model API it binds to, exactly as the "service's license, not the
client's" rule requires. `from langchain_openai import ChatOpenAI` in domain
code is an *OpenAI* finding.

Two things make wrappers different from a direct SDK import, and both are Tier 2
calls:

1. **A provider-agnostic wrapper may itself be the abstraction.** Code written
   against LangChain's `BaseChatModel` with the concrete provider selected at
   composition time is doing what an adapter does — the swap is a config change,
   not a rewrite. Code that imports `ChatOpenAI` directly into a use case and
   passes OpenAI-specific kwargs is not.
2. **LiteLLM is a router, not a vendor client.** Its whole purpose is provider
   substitution, so `litellm.completion(model=...)` with the model name supplied
   by config reduces lock-in. A hardcoded proprietary model string in domain
   code still binds you to that vendor.

Either way the wrapper import is worth surfacing in Tier 1 — decide the role in
Tier 2, and name the underlying vendor in the finding title.

## Mobile Binding Attribution

React Native, the Expo SDK, and most RN community modules are MIT-licensed, so
the same rule the LLM wrappers get applies here: **the binding is never the
finding** — attribute it to the proprietary service it reaches.
`@react-native-firebase/firestore` in a screen is a *Firebase* finding;
`react-native-purchases` is a *RevenueCat* finding; `@stripe/stripe-react-native`
is a *Stripe* finding. Say the service in the finding title, not the npm name.

Never findings on their own: `react-native` itself, `expo` / the Expo SDK
modules that wrap OS APIs (`expo-camera`, `expo-file-system`),
`@react-native-async-storage/async-storage`, `react-native-mmkv`,
`react-navigation`, `react-native-reanimated`. These are open source and
self-hostable-by-definition — flagging them is the mobile version of flagging
`react`, which R1 forbids.

Two mobile-specific judgment calls, both Tier 2:

1. **The scan lists a module under two groups on purpose.**
   `@react-native-firebase/auth` hits both the Firebase group and the mobile
   group; that is one finding naming Firebase, not two.
2. **Native declarations are wiring, not usage.** A `pod 'Firebase/Analytics'`
   or `com.google.gms.google-services` line proves the vendor is installed and
   tells you which native services are enabled, but `ios/Podfile` and
   `android/app/build.gradle` are the mobile composition root — classify them as
   Bootstrap (R2) and hang the severity on what the JS/Swift/Kotlin *code* does.
   Their value is coverage: they reveal Firebase products (Crashlytics,
   Messaging, Remote Config) that the JS bundle never imports.

**Expo/EAS hosted services have no scan pattern.** EAS Build, EAS Submit, EAS
Update (`expo-updates`), and Expo's push service (`expo-notifications`,
`expo-server-sdk`) are proprietary hosted services on top of an MIT SDK, and
`scripts/scan.sh` does not search for them. Their absence from the scan output
is untested, not clean — if `eas.json` or `expo-updates` shows up in Step 1,
judge it in Step 2's residual pass and grep for it explicitly in Step 3.

## Commonly Missed Proprietary Dependencies

**This is a seed list, not an allowlist.** It exists to make SKILL.md Step 2's
residual judgment pass cheap for the usual suspects. A dependency's *absence*
from this list says nothing about it — Step 2 still requires an explicit
proprietary-or-open call on every unmatched manifest entry. There are no
patterns for these in `scripts/scan.sh`; when Step 2 flags one, Step 3 greps
for its import name directly.

Licenses below are stated as of 2026-08 because model training data on vendor
relicensing is reliably stale. Verify before overriding a finding.

| Dependency (import name) | Service | License situation |
|---|---|---|
| `@sentry/*`, `sentry-sdk` | Sentry error tracking | SDKs are MIT; the server is FSL (not OSI-approved, converts to Apache-2.0 after 2 years). Self-hosting is supported, so a self-hosted deployment is materially less lock-in than sentry.io — say which one the repo targets. |
| `elasticsearch`, `@elastic/elasticsearch`, `@elastic/*` | Elasticsearch / Kibana | Version-dependent: SSPL/ELv2 only through 8.15; 8.16+ (2024) added an AGPLv3 option, which is OSI-approved. Check the version pinned in the manifest. Elastic Cloud is a hosted proprietary service regardless. OpenSearch (Apache-2.0) is the open fork. |
| `pinecone-client`, `@pinecone-database/pinecone` | Pinecone vector DB | Fully proprietary hosted service, no self-host path. Finding. (Contrast: Qdrant, Milvus, Chroma are Apache-2.0 and Weaviate core is BSD-3 — those are only lock-in when their *hosted* tier is used.) |
| `launchdarkly-*`, `@launchdarkly/*` | LaunchDarkly feature flags | Proprietary SaaS. Finding. |
| `snowflake-connector-*`, `snowflake-sdk` | Snowflake | Proprietary warehouse. Finding. |
| `databricks-*`, `databricks-sql-connector` | Databricks | Proprietary platform (Spark itself is Apache-2.0; the platform is not). Finding. |
| `contentful`, `@contentful/*`, `@sanity/client` | Contentful / Sanity CMS | Proprietary hosted CMS. Finding. |
| `cloudinary` | Cloudinary media | Proprietary hosted service. Finding. |
| `@vercel/kv`, `@vercel/blob`, `@vercel/postgres`, `@netlify/*` | Vercel / Netlify platform primitives | Proprietary platform bindings — the wire protocol may be open (Postgres) but the binding is not portable. Finding. |
| `terraform` tooling, `cdktf` | HashiCorp Terraform | BUSL-1.1 since 2023, not OSI-approved. OpenTofu is the MPL-2.0 fork. Finding. |
| `confluent-kafka`, `@confluentinc/*` | Confluent Platform | Confluent Community License is not OSI-approved. Apache Kafka itself is Apache-2.0 — the finding is Confluent-specific components (Schema Registry, ksqlDB, Confluent Cloud), not Kafka. |
| `react-native-purchases`, `purchases-*` | RevenueCat subscriptions | SDKs are MIT; the billing/entitlement backend is a proprietary hosted service with no self-host path. Finding — and note that it also mediates the App Store / Play Billing lock-in underneath. |
| `react-native-onesignal`, `onesignal-*` | OneSignal push/messaging | Proprietary SaaS. Finding. The underlying transports (APNs, FCM) are platform-proprietary regardless of which push vendor sits on top. |
| `react-native-branch`, `appsflyer-react-native-plugin`, `react-native-adjust` | Branch / AppsFlyer / Adjust attribution | Proprietary attribution SaaS, deeply coupled to deep-link and install-referrer flows. Finding. |
| `react-native-code-push`, `appcenter-*` | Microsoft App Center / CodePush | Proprietary; App Center was retired in March 2025, so an existing dependency is also dead weight. Migration targets are EAS Update (proprietary) or a self-hosted OTA server. Finding. |
| `react-native-iap`, `expo-in-app-purchases` | App Store / Google Play billing | The library is MIT; the billing rails are the platform's and cannot be swapped while shipping through those stores. Flag as platform lock-in with the caveat that it is not avoidable by architecture alone — an adapter still isolates the blast radius. |
| `@planetscale/database`, `@neondatabase/serverless`, `@upstash/*` | Serverless DB platforms | Open protocol (MySQL/Postgres/Redis) reached through a proprietary platform-specific driver. Flag the driver coupling, note that the data layer itself is portable. |

### Ripgrep One-Liners

Run these in parallel from the repo root.

Skip globs: ripgrep respects `.gitignore` by default, so the usual build and
dependency directories (`node_modules`, `dist`, `build`, `.venv`,
`__pycache__`, `target`, `.next`, `coverage`) are already excluded when they
are gitignored — do not pass them explicitly. Only add `--glob` for cases
ripgrep will not skip on its own:

- `--glob '!**/vendor/**'` — Go/PHP `vendor/` dirs are often committed (the
  `**/` prefix matches `vendor/` at any depth, not just the repo root).
- `--glob '!**/*.lock'` `--glob '!**/package-lock.json'` — lock files can
  contain vendor package names and produce noise.
- `--glob '!**/*.md'` — exclude docs/READMEs from vendor sweeps; they mention
  vendor names in prose, not in code.
- `--glob '!**/Pods/**'` `--glob '!**/*.pbxproj'` `--glob '!**/.expo/**'` — in
  iOS/React Native repos, CocoaPods dependencies are sometimes committed, and
  the Xcode project file and Expo cache are generated artifacts that restate
  every pod name. The Podfile and `build.gradle` are the sources of truth.

Patterns use `-i` (case-insensitive, so `Twilio`/`SENDGRID` match) and word
boundaries (`\b...\b`) where a bare vendor name would otherwise match
substrings and prose. Restrict to source globs (e.g. `--glob '*.ts'`) when a
pattern is still too noisy.

```bash
# One line per vendor group, in scripts/scan.sh order. The pattern strings are
# copied verbatim from the script, so a script-less run is comparable to a
# scripted one. Add the exclusions above as needed, e.g.:
#   rg -in "\btwilio\b" --glob '!**/*.md' --glob '!**/vendor/**'
# Firebase
rg -in "@react-native-firebase|from ['\"]firebase|require\\(['\"]firebase|firebase[-_](admin|functions)|\\bimport firebase|@angular/fire|\\b(reactfire|vuefire)\\b|react-firebase-hooks|firestore\\(|getFirestore|\\bgetAuth\\(|onAuthStateChanged|createUserWithEmailAndPassword|signInWith(EmailAndPassword|Credential|CustomToken|Popup|Redirect|PhoneNumber)\\(|onSnapshot\\(|firebase\\.google\\.com/go|com\\.google\\.firebase|com\\.google\\.gms\\.google-services|GoogleService-Info|\\bFirebase(Admin|App|Core|Firestore|Auth|Storage|Messaging|Analytics|Crashlytics|RemoteConfig)\\b|pod ['\"]Firebase"
# React Native / mobile vendor SDKs (attribute to the underlying service - classification-rules R4)
rg -in "@react-native-firebase/|react-native-purchases|\\brevenuecat\\b|react-native-onesignal|\\bonesignal\\b|react-native-google-mobile-ads|react-native-fbsdk|@react-native-google-signin|@stripe/stripe-react-native|react-native-maps|@sentry/react-native|@bugsnag/react-native|react-native-branch|\\bappsflyer\\b|react-native-adjust|@intercom/intercom-react-native|react-native-zendesk|react-native-code-push|\\bappcenter-|react-native-iap|expo-in-app-purchases|@segment/analytics-react-native|@amplitude/analytics-react-native|mixpanel-react-native|posthog-react-native|@react-native-community/push-notification-ios"
# Google Maps
rg -in "@googlemaps|google\\.maps|googlemaps\\.Client|new google\\.|googlemaps\\.github\\.io/maps|\\bimport GoogleMaps\\b|pod ['\"]GoogleMaps|com\\.google\\.android\\.gms\\.maps"
# Stripe
rg -in "from ['\"]stripe['\"]|require\\(['\"]stripe|import Stripe|\\bstripe\\.[a-zA-Z]|stripe/stripe-go|using Stripe\\b|\\bStripeConfiguration\\b|com\\.stripe\\.android"
# MongoDB
rg -in "\\bMongoClient\\b|require\\(['\"](mongodb|mongoose)|\\bmongoose\\b|\\bpymongo\\b|com\\.mongodb|go\\.mongodb\\.org|mongo-driver|MongoDB\\.Driver"
# Twilio / SendGrid
rg -in "\\btwilio\\b|require\\(['\"](twilio|@sendgrid)|@sendgrid|\\bsendgrid\\b"
# AWS (non-S3 - filter S3-only per classification-rules R4)
rg -in "aws-sdk|\\bboto3\\b|@aws-sdk|aws-amplify|@aws-amplify/|com\\.amazonaws|software\\.amazon\\.awssdk|\\bAWSSDK\\b|using Amazon\\."
# Azure
rg -in "@azure/|azure\\.identity|azure\\.storage|azure-sdk-for-go|using Azure\\.|Microsoft\\.Azure\\."
# Google Cloud
rg -in "@google-cloud/|google\\.cloud\\.|cloud\\.google\\.com/go"
# Algolia
rg -in "algoliasearch|@algolia/"
# Auth0 / Okta
rg -in "\\bauth0\\b|@auth0/|@okta/|okta-auth"
# Analytics (Segment/Mixpanel/Amplitude/PostHog)
rg -in "segment\\.io|\\bmixpanel\\b|\\bamplitude\\.|\\bposthog\\b"
# Observability (Datadog/New Relic)
rg -in "\\bdatadog\\b|dd-trace|\\bnewrelic\\b|@datadog/"
# OpenAI (check for base_url override - classification-rules R4/R5)
rg -in "from ['\"]?openai\\b|require\\(['\"]openai|\\bimport openai\\b|\\bOpenAI\\(|\\bAzureOpenAI\\(|\\bopenai\\.[a-zA-Z]"
# Anthropic
rg -in "@anthropic-ai/|from ['\"]?anthropic\\b|\\bimport anthropic\\b|\\bAnthropic\\(|AnthropicBedrock|AnthropicVertex|\\banthropic\\.[a-zA-Z]"
# Google Gemini
rg -in "@google/generative-ai|@google/genai|google-genai|google[-.]generativeai|google import genai|\\bGoogleGenerativeAI\\b|\\bgenai\\.[a-zA-Z]"
# Cohere
rg -in "cohere-ai|from ['\"]?cohere\\b|\\bimport cohere\\b|\\bCohereClient\\b|\\bcohere\\.[a-zA-Z]"
# Mistral
rg -in "@mistralai/|from ['\"]?mistralai\\b|\\bimport mistralai\\b|\\bMistralClient\\b|\\bMistral\\(|\\bmistralai\\.[a-zA-Z]"
# LLM wrapper SDKs (attribute to the underlying vendor - classification-rules R4)
rg -in "langchain[_.-](openai|anthropic|google_genai|google-genai|google_vertexai|cohere|mistralai|aws)|@langchain/(openai|anthropic|google-genai|google-vertexai|cohere|mistralai|aws)|@ai-sdk/(openai|anthropic|google|mistral|cohere|amazon-bedrock)|llama[_-]index\\.llms\\.[a-z]|\\bChat(OpenAI|Anthropic|GoogleGenerativeAI|VertexAI|Bedrock|Cohere|MistralAI)\\b|\\bAzureChatOpenAI\\b|\\blitellm\\b"
# Vendor API endpoints, raw HTTP (deliberately noisy - Tier 2 prunes)
rg -in "api\\.(stripe|openai|anthropic|twilio|sendgrid|cohere|mistral|mixpanel|amplitude|segment|contentful|pinecone|notion|airtable)\\.(com|io|ai)|api\\.datadoghq\\.com|\\.googleapis\\.com|\\.firebaseio\\.com|hooks\\.slack\\.com|\\.openai\\.azure\\.com|\\.algolia(net)?\\.(com|net)|ingest\\.sentry\\.io|\\.snowflakecomputing\\.com|app\\.launchdarkly\\.com"
```

Three groups overlap the direct-SDK sweeps on purpose — `api.stripe.com` matches
the Stripe pattern too, `llama_index.llms.openai` matches the OpenAI one, and
`@react-native-firebase/auth` matches both the mobile group and Firebase. A file
appearing under several vendor groups is expected; it still yields **one**
finding, naming every vendor involved (SKILL.md Step 3).

## Non-Violation Patterns (do not flag)

These patterns look like dependencies but should not be counted as violations:

```typescript
// Type-only import where domain types are used at runtime
import type { Stripe } from 'stripe';

// SDK referenced inside a clearly named adapter that implements an interface
// File: src/adapters/stripe-payment.adapter.ts
import Stripe from 'stripe';
export class StripePaymentAdapter implements PaymentService { ... }

// SDK referenced from the composition root only
// File: src/bootstrap/container.ts
import Stripe from 'stripe';
container.bind(PaymentService).toConstantValue(new StripePaymentAdapter(new Stripe(...)));
```

```python
# AWS SDK used only for S3 — acceptable (S3 protocol is open)
import boto3
s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
```

```python
# NOT a violation: base_url resolves to a self-hostable, open-weight runtime —
# reduced lock-in (like S3's endpoint_url). The same code runs against vLLM,
# Ollama, LiteLLM, LocalAI, or TGI, so the OpenAI service is swappable.
# The endpoint is knowable from the source: the default names Ollama.
from openai import OpenAI
client = OpenAI(
    base_url=os.environ.get("LLM_BASE_URL", "http://localhost:11434/v1"),
    api_key=os.environ.get("LLM_KEY", "ollama"),
)
```

```python
# INDETERMINATE — do NOT treat this as the case above. With no default, the
# endpoint is unknowable from this file: at deploy time LLM_BASE_URL could be
# vLLM (acceptable), Groq (a finding, re-attributed), or unset and falling back
# to api.openai.com (a finding). Resolve it from .env.example / compose /
# deployment config; if it stays indeterminate, keep the finding at Low or
# Medium with an ambiguity note. Never reject on an unresolvable env var.
from openai import OpenAI
client = OpenAI(base_url=os.environ["LLM_BASE_URL"], api_key=os.environ["LLM_KEY"])
```

Caveat for the LLM case: a `base_url`/`baseURL` override is acceptable only when it
**demonstrably** points at a self-hostable / open-weight runtime. If it points at
another proprietary SaaS (Azure OpenAI, Groq, Together, Perplexity) or the call
uses Bedrock/Vertex, it is still a finding — re-attribute it to that vendor. With
no override at all, treat it as the vendor's default hosted API (a finding). The
exception rewards a codebase that *shows* its endpoint is open, not one that
merely hides the endpoint behind a variable.

Where to resolve an env-var endpoint (in this order — stop at the first hit):

1. A literal default in the call itself (`os.environ.get(..., "http://...")`,
   `process.env.X ?? "http://..."`).
2. `.env.example`, `.env.sample`, `.env.defaults`, `.env.template`.
3. `docker-compose*.yml` (an `ollama`/`vllm`/`litellm` service alongside the app
   is strong evidence), Helm `values.yaml`, k8s manifests, Terraform.
4. Config modules with a fallback constant, CI workflow env blocks, README or
   deployment docs.

If none of these settle it, the finding survives with the ambiguity documented —
a shrug is not an acquittal.

When you see these shapes, classify the file as Adapter, Bootstrap, or Acceptable and exclude it from the violation list.
