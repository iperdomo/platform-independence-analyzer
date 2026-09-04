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

Module paths, not bare package names - this is why the JS/Python patterns miss
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
and the native projects declare the same vendors again in CocoaPods and Gradle -
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
`@react-native-async-storage/async-storage` are MIT - never findings on their
own. See "Mobile Binding Attribution" below.

### PHP

The largest ecosystem in the DPG population (tens of thousands of files across
Moodle, Dolibarr forks, Laravel apps and bespoke REST backends), so scanner
silence here would be the single loudest false negative. Vendors arrive as
namespace imports, and much of what a grep finds lives in a *committed*
third-party tree - see `triage-and-noise.md` before counting hits.

```php
// Direct usage - VIOLATION
use Stripe\StripeClient;
use Twilio\Rest\Client;
use MongoDB\Client;
use Aws\S3\S3Client;
use Google\Cloud\Storage\StorageClient;
use Kreait\Firebase\Factory;
\Stripe\Stripe::setApiKey($key);
$client = new Google_Client();       // older style, still common in Moodle

// Abstracted - GOOD
use App\Contracts\PaymentGateway;   // bound to a driver in a service provider
```

Framework config is evidence in its own right: Laravel `config/services.php`
and `config/mail.php` driver blocks name the vendor even when no PHP file
imports it, and a bespoke `config/*.php` can hardcode a third-party gateway URL
that appears nowhere else.

### Dart / Flutter

Plugins are declared in `pubspec.yaml` and imported as `package:` URIs. The
same vendor is often reached twice - once from Dart, once from native Swift or
Kotlin - and the checked-in iOS `Podfile` lists nothing, because Flutter
generates pods from `.flutter-plugins-dependencies` at build time.

```dart
// Direct usage - VIOLATION
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Abstracted - GOOD
import '../data/crop_repository.dart';
```

```swift
// ios/Runner/AppDelegate.swift - the SAME Google Maps dependency, declared again
GMSServices.provideAPIKey("...")
```

### Objective-C

Swift-oriented patterns miss `.m`/`.h` files entirely, and iOS apps routinely
wire their vendors there.

```objc
#import <FirebaseCore/FirebaseCore.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <Lokalise/Lokalise.h>
[FIRApp configure];
[[Lokalise sharedObject] setProjectID:LOKALISE_PROJECT_ID token:LOKALISE_TOKEN];
```

Note the shape of the last line: vendor SDKs in Objective-C entry points often
sit next to a hardcoded token. Mention it in the finding (see
`classification-rules.md`), never make it the finding.

### Clojure / Scala

Coordinates in `deps.edn` / `project.clj`, and JVM-style imports in source. A
whole cloud SDK can be declared only in a nested `deps.edn`.

```clojure
;; deps.edn - the only place this dependency is named
{:deps {com.cognitect.aws/api {...} com.cognitect.aws/s3 {...}}}
```

```scala
import com.mongodb.spark.MongoSpark          // VIOLATION
import com.mongodb.spark.config._
```

### Ruby and Rust - still not pattern-covered

`scripts/scan.sh` has no patterns for these two. Their manifests (`Gemfile`,
`Cargo.toml`) are still read in Step 1 and judged in Step 2, so the vendor
names are known - Step 3 must grep for them explicitly rather than trusting the
scanner's silence. Typical shapes:

- Ruby: `Stripe::`, `Twilio::REST`, `Mongoid`, `Google::Cloud`, `require "stripe"`
- Rust: `stripe_rust`, `mongodb::`, `aws_sdk_`, `google_cloud_`

### Build-system indirection - the vendor name is not where you expect it

Three shapes where a coordinate-keyed pattern finds nothing because the
coordinate has been factored out:

1. **Gradle version catalogs.** Modules reference `libs.playServicesMaps` or
   `libs.firebaseCrashlytics`; the actual `com.google.android.gms:...`
   coordinate exists once, in `gradle/libs.versions.toml`. The catalog file
   itself is matched by the vendor patterns; the *alias* references are what
   tell you how many modules are affected. Count them - that is the blast
   radius.
2. **Typed project accessors.** `implementation(projects.libraries.pushproviders.firebase)`
   names an internal module, not a vendor. Follow the accessor to the module,
   then judge that module.
3. **Vendors entering as PLUGINS, not dependencies.**
   `apply plugin: 'com.google.firebase.crashlytics'`,
   `id("com.google.gms.google-services")`, or a `classpath` entry in the root
   build file. A plugin adds a vendor to the build without a single
   `implementation` line.

**Declared-but-dark vs wired-but-undeclared.** Check both directions, because
each produces a different error:

- A Gradle *classpath* entry for a vendor plugin that is never applied, and no
  `google-services.json` anywhere, is a dead declaration - not usage, and
  flagging it is a false positive.
- The reverse is worse: an iOS `Podfile` with no Firebase entry while
  `AppDelegate.m` calls `[FIRApp configure]` and a `GoogleService-Info.plist`
  sits beside it. Manifest-only reasoning reports that app as Firebase-free.
  `scan.sh` prints a **VENDOR CONFIG FILES PRESENT** section for exactly this
  case: those files' presence is the evidence, since their contents may name no
  vendor at all.

Config-file wiring is Bootstrap (R2): use it for *coverage* - which vendor
products are actually enabled - not for severity.

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
or a config file is **Acceptable** - it is not a violation on its own. Config
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
call scattered through domain code is the violation - because of the direct
SDK use in domain code, not because the config mentions a vendor.

## Common Anti-Patterns

Vendor-lock-in shapes to flag (in scope for this skill):

1. **Scattered API calls**: vendor SDK calls throughout business logic.
2. **Direct SDK usage**: using vendor SDKs directly in domain code instead of
   through an adapter/port/repository.
3. **Vendor types in public interfaces**: an abstraction exists but leaks
   vendor types through its public surface.

Out of scope (do NOT flag - these are architectural-quality concerns, not
lock-in): general tight coupling, missing interfaces around open-source
libraries, or config that merely names a vendor. See classification-rules R1
for the full scope boundary.

## Detection Keywords

This list and `references/patterns.tsv` do different jobs, and the difference
matters. The TSV is what gets **scanned** - deterministic, reproducible,
mechanical. This list is what gets **judged** in Step 2, and it is deliberately
wider: it names services whose only trace may be a manifest entry, an env var,
or a config file that no source-code pattern would ever match. A name here with
no pattern in the TSV is not an oversight; it is a name to grep for explicitly
when Step 2 finds it declared.

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
- `aws-sdk`, `boto3`, `@aws-sdk` (filter S3-only out - see acceptable list)
- `azure-`, `@azure/`
- `@google-cloud/`, `google.cloud.`
- `algolia`, `@algolia/`
- `auth0`, `@auth0/`, `okta`, `@okta/`
- `segment`, `mixpanel`, `amplitude`, `posthog`
- `datadog`, `newrelic`, `dd-trace`, `@datadog/`
- `pusher`, `pubnub`, `ably`
- `mapbox`, `here-`, `@here/`
- `intercom`, `zendesk`, `salesforce`, `@salesforce/`
- React Native / mobile bindings (the module is the wrapper - name the service
  it binds to; see "Mobile Binding Attribution" below):
  - `@react-native-firebase/*` -> Firebase
  - `react-native-purchases` -> RevenueCat; `react-native-iap`,
    `expo-in-app-purchases` -> App Store / Play Billing
  - `react-native-onesignal` -> OneSignal; `@react-native-community/push-notification-ios` -> APNs
  - `react-native-google-mobile-ads` -> Google AdMob; `react-native-fbsdk-next` -> Meta
  - `@react-native-google-signin/google-signin` -> Google Identity
  - `@stripe/stripe-react-native` -> Stripe; `react-native-maps` -> Google/Apple Maps
  - `@sentry/react-native` -> Sentry; `@bugsnag/react-native` -> Bugsnag
  - `react-native-branch`, `appsflyer-react-native-plugin`, `react-native-adjust`
    -> attribution SaaS (Branch, AppsFlyer, Adjust)
  - `@intercom/intercom-react-native`, `react-native-zendesk` -> Intercom, Zendesk
  - `react-native-code-push`, `appcenter-*` -> Microsoft App Center
  - `@segment/analytics-react-native`, `@amplitude/analytics-react-native`,
    `mixpanel-react-native`, `posthog-react-native` -> the analytics vendor
  - `aws-amplify`, `@aws-amplify/*` -> AWS (matches neither `aws-sdk` nor `@aws-sdk`)
- LLM/AI SaaS APIs (proprietary services behind permissively licensed SDKs -
  the service, not the client license, creates the lock-in):
  - `openai`, `OpenAI`, `AzureOpenAI` (see the base_url note under acceptable patterns)
  - `@anthropic-ai/sdk`, `anthropic`, `Anthropic`, `AnthropicBedrock`, `AnthropicVertex`
  - `@google/generative-ai`, `@google/genai`, `google-generativeai`, `google-genai`, `genai`
  - `cohere-ai`, `cohere`, `CohereClient`
  - `@mistralai/mistralai`, `mistralai`, `MistralClient`
  - OpenAI-compatible providers (Groq, Together, Perplexity, Fireworks, ...) are
    usually reached via the OpenAI SDK with a `base_url` - they surface under the
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

### Vendor classes added from the DPG corpus

Grouped as they are grouped in `patterns.tsv`. Every one of these was the sole
vendor coupling in at least one real repository.

- **Error tracking**: `@sentry/*`, `sentry-sdk`, `io.sentry`, `@bugsnag/*`,
  `rollbar`, `raygun`, `airbrake`.
- **Realtime messaging SaaS**: `pusher`, `pusher-js`, `pubnub`, `ably`.
- **Data / search / flags / CMS**: `elasticsearch`, `@elastic/*`, `snowflake`,
  `databricks`, `pinecone`, `launchdarkly`, `contentful`, `@sanity/client`,
  `cloudinary`, `tinybird`, `@vercel/*`, `@netlify/*`, `@planetscale/*`,
  `@neondatabase/*`, `@upstash/*`.
- **Support / CRM**: `intercom`, `zendesk`, `salesforce`, `hubspot`,
  `freshdesk`, `freshchat`.
- **Payments beyond Stripe**: `paypal`, `braintree`, M-Pesa / `daraja` /
  `safaricom`, `flutterwave`, `paystack`, `razorpay`, `payu`, `mollie`,
  `adyen`, `wompi`, `yoco`. Regionally critical: outside the US and EU these
  are usually the *only* payment path, so a Stripe-shaped pattern list reports
  a payment-integrated app as payment-free.
- **Email delivery**: `mailgun`, `postmark`, `mailchimp` / `mandrill`,
  `sparkpost`, `mailjet`, `brevo` / `sendinblue`, Amazon SES. Also read
  Laravel `config/services.php` and `config/mail.php` driver blocks - the
  vendor is often named only there.
- **SMS and chat**: Africa's Talking, `messagebird`, `clickatell`, `vonage` /
  `nexmo`, `infobip`, WhatsApp Business Cloud API (`graph.facebook.com`),
  Telegram Bot API (`api.telegram.org`, `python-telegram-bot`, `telegraf`),
  Slack SDKs (`@slack/web-api`, `slack_sdk` - not just `hooks.slack.com`),
  Discord.
- **Hosted AI/ML beyond the big-5 LLM vendors**: `replicate`, `fal.ai`,
  `modal` (serverless GPU), `deepgram`, `elevenlabs`, `assemblyai`, `sarvam`,
  `ghananlp`, `lelapa` / `vulavula`, `intron-health`, `uberduck`, `groq`,
  `fireworks.ai`, `openrouter`, `huggingface_hub` (hosted inference and gated
  tokens - NOT open-weight downloads), `langfuse`, `clearml`, `roboflow`,
  `composio`, `livekit`, Vespa Cloud, Google ML Kit (`com.google.mlkit`),
  Google Cloud Translate/Speech/Vision (`*.googleapis.com`), Azure Cognitive
  Services (`cognitiveservices`, `form-recognizer`, `azure-ai-*`).
- **Geospatial**: `mapbox`, `arcgis` / `esri`, Google Earth Engine, HERE,
  `play-services-maps` / `play-services-location`, `google_maps_flutter`,
  `GMSServices` (native iOS). See "Open geospatial stacks" below for the ones
  that must never be flagged.
- **Web platform services**: Google reCAPTCHA, hCaptcha, Cloudflare Turnstile,
  Google Analytics / GTM (including hardcoded `UA-*`, `G-*`, `GTM-*` IDs in
  `index.html`), `hotjar`, `heap`, `akismet`, `unsplash`, `lokalise`,
  `typeform`, `disqus`, `crowdin`.
- **Blockchain RPC and ledger**: `infura`, `alchemy`, `covalent`, `moralis`,
  `etherscan`, `walletconnect`, `quicknode`, `ankr`, `thirdweb`, AWS QLDB.
- **Proprietary database and log-store drivers**: Oracle
  (`Oracle.ManagedDataAccess`, `System.Data.OracleClient`, `cx_Oracle`,
  `ojdbc`), SQL Server (`Microsoft.Data.SqlClient`, a raw `new SqlConnection`,
  `jdbc:sqlserver`), Firebird, TigerBeetle, Seq/Datalust
  (`Serilog.Sinks.Seq`).
- **Game and desktop platform SDKs**: AdMob (often only as a Cordova plugin
  name string), Facebook Instant Games (`FBInstant`), Steamworks, Discord
  RPC/Game SDK, Epic Online Services.

### Open geospatial stacks - never flag

MapLibre GL, Leaflet, OpenLayers, osmdroid, and OpenStreetMap tile usage are
open source and open data. Flagging them is the geospatial version of flagging
`react`. A mapping module named after a vendor is not automatically a finding:
a repository carrying **both** a Mapbox adapter and an osmdroid adapter behind
one maps interface is demonstrating the abstraction this audit asks for -
classify it as an adapter set (R2a), not as two vendor couplings. Self-hosted
Nominatim, Photon, and tile servers are likewise not lock-in.

### First-party closed SaaS backends

Some projects call *their own* hosted service - a single hardcoded API host
that no third-party SDK names, and that only the project's maintainers can
operate (a game engine calling its own asset and AI-generation endpoints, a
mobile client whose only server is the vendor's). No vendor pattern will ever
match it, because the vendor is the project itself.

Treat a first-party closed backend as a **finding when the repository is meant
to be deployable by others**: a self-hoster gets the code but not the service,
which is precisely lock-in. Name it as such ("first-party closed SaaS
backend"), cite the hardcoded host, and say whether an alternative host is
configurable. Where the repository is only ever run by the vendor themselves,
it is informational instead. The signal to look for is a hardcoded
`api.<project>.io`-style constant with no override path.

### Dual-licensed (AGPL-or-commercial) libraries

`iText`, `JasperReports`, `Highcharts` and their kin ship under an OSI-approved
copyleft licence *or* a paid commercial licence. R1's test is satisfied - an
OSI-approved option exists - so these are **not findings**.

They are also not nothing: a project that cannot comply with AGPL/GPL terms is
buying a per-seat licence from a single vendor, and that is real commercial
dependence. Record them under **Acceptable Dependencies** with a one-line
"commercial-licence coupling" note naming the library, the copyleft obligation,
and the fact that a proprietary deployment requires the paid licence. Do not
assign a severity.

## LLM Wrapper Attribution

LangChain, LlamaIndex, the Vercel AI SDK, and LiteLLM are themselves MIT- or
Apache-licensed. **The wrapper is never the finding** - attribute it to the
proprietary model API it binds to, exactly as the "service's license, not the
client's" rule requires. `from langchain_openai import ChatOpenAI` in domain
code is an *OpenAI* finding.

Two things make wrappers different from a direct SDK import, and both are Tier 2
calls:

1. **A provider-agnostic wrapper may itself be the abstraction.** Code written
   against LangChain's `BaseChatModel` with the concrete provider selected at
   composition time is doing what an adapter does - the swap is a config change,
   not a rewrite. Code that imports `ChatOpenAI` directly into a use case and
   passes OpenAI-specific kwargs is not.
2. **LiteLLM is a router, not a vendor client.** Its whole purpose is provider
   substitution, so `litellm.completion(model=...)` with the model name supplied
   by config reduces lock-in. A hardcoded proprietary model string in domain
   code still binds you to that vendor.

Either way the wrapper import is worth surfacing in Tier 1 - decide the role in
Tier 2, and name the underlying vendor in the finding title.

## Mobile Binding Attribution

React Native, the Expo SDK, and most RN community modules are MIT-licensed, so
the same rule the LLM wrappers get applies here: **the binding is never the
finding** - attribute it to the proprietary service it reaches.
`@react-native-firebase/firestore` in a screen is a *Firebase* finding;
`react-native-purchases` is a *RevenueCat* finding; `@stripe/stripe-react-native`
is a *Stripe* finding. Say the service in the finding title, not the npm name.

Never findings on their own: `react-native` itself, `expo` / the Expo SDK
modules that wrap OS APIs (`expo-camera`, `expo-file-system`),
`@react-native-async-storage/async-storage`, `react-native-mmkv`,
`react-navigation`, `react-native-reanimated`. These are open source and
self-hostable-by-definition - flagging them is the mobile version of flagging
`react`, which R1 forbids.

Two mobile-specific judgment calls, both Tier 2:

1. **The scan lists a module under two groups on purpose.**
   `@react-native-firebase/auth` hits both the Firebase group and the mobile
   group; that is one finding naming Firebase, not two.
2. **Native declarations are wiring, not usage.** A `pod 'Firebase/Analytics'`
   or `com.google.gms.google-services` line proves the vendor is installed and
   tells you which native services are enabled, but `ios/Podfile` and
   `android/app/build.gradle` are the mobile composition root - classify them as
   Bootstrap (R2) and hang the severity on what the JS/Swift/Kotlin *code* does.
   Their value is coverage: they reveal Firebase products (Crashlytics,
   Messaging, Remote Config) that the JS bundle never imports.

**Expo/EAS hosted services and dynamic Expo config.** EAS Build, EAS Submit,
EAS Update (`expo-updates`) and Expo's push service (`expo-notifications`,
`expo-server-sdk`) are proprietary hosted services on top of an MIT SDK. They
now have their own scan group, plus an `eas.json` presence check.

Two traps specific to Expo:

- **`app.config.js` / `app.config.ts` is executable and overrides `app.json`.**
  Keys arrive through `process.env.EXPO_PUBLIC_*`, so the static `app.json` can
  look clean while the effective config wires a vendor. Read the dynamic config
  when one exists; judging from `app.json` alone is a false negative.
- **Declared but dark.** A dependency on App Center / CodePush
  (`appcenter-*`, `react-native-code-push`) with zero imports in source is a
  dead declaration, not usage - worth one line in Acceptable Dependencies with
  the note that App Center was retired in March 2025, not a finding. Check both
  directions before writing either verdict.

## Commonly Missed Proprietary Dependencies

**This is a seed list, not an allowlist.** It exists to make SKILL.md Step 2's
residual judgment pass cheap for the usual suspects. A dependency's *absence*
from this list says nothing about it - Step 2 still requires an explicit
proprietary-or-open call on every unmatched manifest entry. There are no
patterns for these in `scripts/scan.sh`; when Step 2 flags one, Step 3 greps
for its import name directly.

Licenses below are stated as of 2026-08 because model training data on vendor
relicensing is reliably stale. Verify before overriding a finding.

| Dependency (import name) | Service | License situation |
|---|---|---|
| `@sentry/*`, `sentry-sdk` | Sentry error tracking | SDKs are MIT; the server is FSL (not OSI-approved, converts to Apache-2.0 after 2 years). Self-hosting is supported, so a self-hosted deployment is materially less lock-in than sentry.io - say which one the repo targets. |
| `elasticsearch`, `@elastic/elasticsearch`, `@elastic/*` | Elasticsearch / Kibana | Version-dependent: SSPL/ELv2 only through 8.15; 8.16+ (2024) added an AGPLv3 option, which is OSI-approved. Check the version pinned in the manifest. Elastic Cloud is a hosted proprietary service regardless. OpenSearch (Apache-2.0) is the open fork. |
| `pinecone-client`, `@pinecone-database/pinecone` | Pinecone vector DB | Fully proprietary hosted service, no self-host path. Finding. (Contrast: Qdrant, Milvus, Chroma are Apache-2.0 and Weaviate core is BSD-3 - those are only lock-in when their *hosted* tier is used.) |
| `launchdarkly-*`, `@launchdarkly/*` | LaunchDarkly feature flags | Proprietary SaaS. Finding. |
| `snowflake-connector-*`, `snowflake-sdk` | Snowflake | Proprietary warehouse. Finding. |
| `databricks-*`, `databricks-sql-connector` | Databricks | Proprietary platform (Spark itself is Apache-2.0; the platform is not). Finding. |
| `contentful`, `@contentful/*`, `@sanity/client` | Contentful / Sanity CMS | Proprietary hosted CMS. Finding. |
| `cloudinary` | Cloudinary media | Proprietary hosted service. Finding. |
| `@vercel/kv`, `@vercel/blob`, `@vercel/postgres`, `@netlify/*` | Vercel / Netlify platform primitives | Proprietary platform bindings - the wire protocol may be open (Postgres) but the binding is not portable. Finding. |
| `terraform` tooling, `cdktf` | HashiCorp Terraform | BUSL-1.1 since 2023, not OSI-approved. OpenTofu is the MPL-2.0 fork. Finding. |
| `confluent-kafka`, `@confluentinc/*` | Confluent Platform | Confluent Community License is not OSI-approved. Apache Kafka itself is Apache-2.0 - the finding is Confluent-specific components (Schema Registry, ksqlDB, Confluent Cloud), not Kafka. |
| `react-native-purchases`, `purchases-*` | RevenueCat subscriptions | SDKs are MIT; the billing/entitlement backend is a proprietary hosted service with no self-host path. Finding - and note that it also mediates the App Store / Play Billing lock-in underneath. |
| `react-native-onesignal`, `onesignal-*` | OneSignal push/messaging | Proprietary SaaS. Finding. The underlying transports (APNs, FCM) are platform-proprietary regardless of which push vendor sits on top. |
| `react-native-branch`, `appsflyer-react-native-plugin`, `react-native-adjust` | Branch / AppsFlyer / Adjust attribution | Proprietary attribution SaaS, deeply coupled to deep-link and install-referrer flows. Finding. |
| `react-native-code-push`, `appcenter-*` | Microsoft App Center / CodePush | Proprietary; App Center was retired in March 2025, so an existing dependency is also dead weight. Migration targets are EAS Update (proprietary) or a self-hosted OTA server. Finding. |
| `react-native-iap`, `expo-in-app-purchases` | App Store / Google Play billing | The library is MIT; the billing rails are the platform's and cannot be swapped while shipping through those stores. Flag as platform lock-in with the caveat that it is not avoidable by architecture alone - an adapter still isolates the blast radius. |
| `@planetscale/database`, `@neondatabase/serverless`, `@upstash/*` | Serverless DB platforms | Open protocol (MySQL/Postgres/Redis) reached through a proprietary platform-specific driver. Flag the driver coupling, note that the data layer itself is portable. |

### License situations for the corpus-derived vendors

Same rules as the table above: stated as of 2026-08, the **service's** licence
decides, and a name's absence from any list means nothing. Listed here are the
ones whose call is *not* obvious - especially the open-core vendors, where the
naive "hosted SaaS = lock-in" reading produces a false positive.

| Dependency / service | Licence situation | Judgment |
|---|---|---|
| Mapbox (`mapbox-gl` v2+, `@mapbox/*`) | Proprietary since GL JS v2; MapLibre GL is the BSD-3 fork of v1 | Finding. MapLibre in the same repo is NOT a finding |
| ArcGIS / Esri, HERE, Google Earth Engine | Proprietary, account-gated | Finding |
| PostHog, Matomo, Umami | Open-source core, self-hostable; the hosted tier is the proprietary part | Resolve the endpoint before judging - self-hosted is not lock-in |
| Langfuse, LiveKit, Vespa, ClearML | Open-source core (MIT/Apache-2) with a proprietary hosted tier | Same endpoint-resolution question as PostHog |
| Tinybird, Heap, Hotjar, Akismet, Unsplash, Lokalise, Crowdin, Typeform, Disqus | Proprietary hosted services | Finding when called from code; a tracking ID in an HTML template is evidence too |
| Google reCAPTCHA, hCaptcha, Cloudflare Turnstile | All proprietary; no drop-in open equivalent in wide use (Altcha and self-hosted alternatives exist) | Finding, with the honest note that the alternatives are weaker |
| Google Analytics / GTM | Proprietary; Matomo/Plausible/Umami are the open replacements | Finding |
| Replicate, fal.ai, Modal, Deepgram, ElevenLabs, AssemblyAI, Sarvam, Uberduck, Roboflow, Composio | Proprietary hosted inference / GPU / ASR / TTS / vision SaaS | Finding |
| Groq, Fireworks, OpenRouter, Together, Perplexity | Proprietary hosted inference, usually reached through the OpenAI SDK with a `base_url` | Finding, re-attributed to the actual provider (R4) |
| HuggingFace Hub | Downloading open-weight models is not lock-in; hosted Inference Endpoints and gated/token-walled models are | Judge by which one the code does |
| GhanaNLP, Lelapa/Vulavula, Intron Health | Proprietary regional-language AI APIs, often the only provider for that language | Finding - and say so plainly: no alternative provider exists today |
| M-Pesa/Daraja, Flutterwave, Paystack, Razorpay, PayPal/Braintree | Proprietary payment APIs | Finding. Note where a market has no alternative rail |
| Africa's Talking, MessageBird, Clickatell, Vonage/Nexmo, Infobip | Proprietary SMS gateways | Finding |
| WhatsApp Business Cloud API, Telegram Bot API | Proprietary platform APIs (`graph.facebook.com`, `api.telegram.org`) | Finding; platform rails, an adapter contains but does not remove it |
| Mailgun, Postmark, Mailchimp/Mandrill, SparkPost, Mailjet, Brevo, Amazon SES | Proprietary email delivery SaaS | Finding. Plain SMTP to a self-hosted MTA is not |
| Pusher, PubNub, Ably | Proprietary realtime SaaS | Finding (open alternatives: Centrifugo, Soketi, plain WebSockets) |
| Infura, Alchemy, QuickNode, Ankr, Covalent, Moralis, Etherscan API | Proprietary hosted blockchain RPC/indexers | Finding, but weight it by shape: an injected provider URL is near-zero switching cost, a hardcoded one is not |
| AWS QLDB | Fully proprietary ledger, no open equivalent, AWS-only (and on a deprecation path) | Finding, high - among the deepest lock-in shapes there is |
| Oracle Database, Microsoft SQL Server | Proprietary servers reached through open-ish drivers | Finding (R1: the server's licence decides) |
| Firebird | IPL/IDPL, open source | Not a finding |
| TigerBeetle | Source-available, single-vendor, no fork ecosystem | Judgment call - flag with the reasoning stated |
| Seq / Datalust (`Serilog.Sinks.Seq`) | Proprietary log server, free single-user tier | Finding, usually Low - a log sink is swappable |
| AdMob, Facebook Instant Games, Steamworks, Epic Online Services | Proprietary platform/ad SDKs | Finding as platform rails; an adapter isolates the blast radius, it does not remove the coupling |
| iText, JasperReports, Highcharts | Dual-licensed: OSI-approved copyleft OR paid commercial | NOT a finding - record under Acceptable Dependencies with a commercial-licence note (see below) |

### Ripgrep One-Liners

**The patterns are not written here.** They live in exactly one place -
`references/patterns.tsv` - and `scripts/scan.sh` reads that file at runtime.
Two hand-maintained copies of a regex drift, and a drifted copy silently
changes what a "reproducible scan" reproduces.

For a script-less run, generate the one-liners instead of retyping them:

```bash
bash <SKILL_DIR>/scripts/scan.sh --print-patterns
```

It prints one `rg -in '<pattern>'` per group, each with its label and its
judgment note, ready to paste. Add the exclusion globs it lists in its header
(`--glob '!**/vendor/**'`, `Pods`, `*.pbxproj`, `.expo`, lock files, `*.md`,
and the audit's own output file).

Skip globs, for reference: ripgrep respects `.gitignore`, so `node_modules`,
`dist`, `build`, `.venv`, `__pycache__`, `target`, `.next` and `coverage` are
already excluded when they are gitignored - do not pass them explicitly. The
globs that matter are the ones ripgrep will not skip on its own: committed
`vendor/` and `Pods/` trees, generated `*.pbxproj` and `.expo/` artifacts, lock
files, and Markdown docs that name vendors in prose.

**Adding a vendor** is a one-line change in `patterns.tsv`: a label, a pattern
(applied with `-i`, so never spell out case variants), and a note carrying the
judgment a bare hit cannot - what to attribute it to, and what must NOT be
flagged. Prefer joining an existing capability group over creating a new one;
the HIT SUMMARY is only useful while it stays readable.

Three groups overlap the direct-SDK sweeps on purpose - `api.stripe.com` matches
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
# AWS SDK used only for S3 - acceptable (S3 protocol is open)
import boto3
s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
```

```python
# NOT a violation: base_url resolves to a self-hostable, open-weight runtime -
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
# INDETERMINATE - do NOT treat this as the case above. With no default, the
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
uses Bedrock/Vertex, it is still a finding - re-attribute it to that vendor. With
no override at all, treat it as the vendor's default hosted API (a finding). The
exception rewards a codebase that *shows* its endpoint is open, not one that
merely hides the endpoint behind a variable.

Where to resolve an env-var endpoint (in this order - stop at the first hit):

1. A literal default in the call itself (`os.environ.get(..., "http://...")`,
   `process.env.X ?? "http://..."`).
2. `.env.example`, `.env.sample`, `.env.defaults`, `.env.template`.
3. `docker-compose*.yml` (an `ollama`/`vllm`/`litellm` service alongside the app
   is strong evidence), Helm `values.yaml`, k8s manifests, Terraform.
4. Config modules with a fallback constant, CI workflow env blocks, README or
   deployment docs.

If none of these settle it, the finding survives with the ambiguity documented -
a shrug is not an acquittal.

When you see these shapes, classify the file as Adapter, Bootstrap, or Acceptable and exclude it from the violation list.
