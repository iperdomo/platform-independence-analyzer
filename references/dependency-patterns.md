# Dependency Patterns Reference

What the scan patterns cannot carry on their own: the shapes vendors take in
each ecosystem, who to attribute a wrapper or binding to, and the dated
license judgments. The patterns themselves live in one place,
`references/patterns.tsv`. This file is one of the two the Tier 2 verifier
reads.

## Per-language shapes

Only the shapes that are easy to miss. A direct vendor import in domain code
is a violation in every language; an import of a project-owned interface is
not.

- **Go**: vendors arrive as module paths (`github.com/stripe/stripe-go/v76`,
  `go.mongodb.org/mongo-driver`, `cloud.google.com/go/storage`,
  `firebase.google.com/go/v4`), which share no substring with the JS or Python
  package names. The idiomatic abstraction is an interface declared in the
  consuming package.
- **.NET / C#**: `using` namespaces (`using Stripe;`, `using MongoDB.Driver;`,
  `using Amazon.DynamoDBv2;`, `using FirebaseAdmin;`). Three declaration styles
  (`PackageReference`, `packages.config`, central `Directory.Packages.props`)
  routinely coexist in one repo.
- **React Native**: three codebases in one directory, and the JS half hides
  the other two. `@react-native-firebase/*` shares no substring with
  `firebase/app`, and `ios/Podfile` and `android/app/build.gradle` declare the
  same vendors again, so `src/` can look Firebase-free while the native
  projects wire it in. See "Mobile Binding Attribution" below.
- **PHP**: the largest ecosystem in the calibration corpus (Moodle, Dolibarr
  forks, Laravel apps), so silence here would be the loudest false negative.
  Vendors arrive as namespace imports (`use Stripe\StripeClient;`,
  `use Kreait\Firebase\Factory;`) or old-style classes (`new Google_Client()`),
  and much of what a grep finds lives in a committed third-party tree - see
  `triage-and-noise.md` T2. Laravel `config/services.php` and
  `config/mail.php` driver blocks name the vendor even when no PHP file
  imports it, and a bespoke `config/*.php` can hardcode a gateway URL that
  appears nowhere else.
- **Dart / Flutter**: plugins are `package:` imports declared in
  `pubspec.yaml`. The same vendor is often reached twice - from Dart and from
  native Swift or Kotlin (`GMSServices.provideAPIKey(...)` in
  `ios/Runner/AppDelegate.swift`) - and the checked-in iOS `Podfile` lists
  nothing, because Flutter generates the pods at build time.
- **Objective-C**: `.m`/`.h` files wire vendors with `#import <FirebaseCore/...>`
  and `[FIRApp configure]`, often next to a hardcoded token
  (`[[Lokalise sharedObject] setProjectID:... token:...]`). Mention the token
  in the finding (R7), never make it the finding.
- **Clojure / Scala**: coordinates live in `deps.edn` / `project.clj` - a
  whole cloud SDK can be declared only in a nested `deps.edn`
  (`com.cognitect.aws/api`) - and source uses JVM-style imports
  (`com.mongodb.spark.MongoSpark`).
- **Ruby**: `require 'stripe'`, `Stripe::`, `Twilio::REST`, `Aws::`,
  `Google::Cloud::`, `OpenAI::Client`, gems such as `sentry-ruby`,
  `newrelic_rpm`, `ddtrace`, `mongoid`.
- **Rust**: `use stripe::`, `async-openai`, `aws_sdk_*` / `aws_config`,
  `mongodb::`, `sentry::`, `tiberius` (SQL Server).

## Build-system indirection - the vendor name is not where you expect it

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

## Configuration is not a violation

Reading vendor configuration (API keys, project IDs, endpoints) from env vars
or a config file is Acceptable on its own: every vendor needs configuration,
however well the code is abstracted. Classify the site by the file's role
(classification-rules R2) - `initializeApp(config)` in a composition root is
Bootstrap; the same call scattered through domain code is a violation because
of the direct SDK use, not because the config names a vendor.

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

| Binding | Service behind it |
|---|---|
| `@react-native-firebase/*` | Firebase |
| `react-native-purchases` | RevenueCat |
| `react-native-iap`, `expo-in-app-purchases` | App Store / Play Billing (platform rails, R4) |
| `react-native-onesignal` | OneSignal |
| `@react-native-community/push-notification-ios` | APNs (platform rails) |
| `react-native-google-mobile-ads` | Google AdMob |
| `react-native-fbsdk-next` | Meta |
| `@react-native-google-signin/google-signin` | Google Identity (platform sign-in, R4) |
| `@stripe/stripe-react-native` | Stripe |
| `react-native-maps` | Google Maps / Apple Maps |
| `@sentry/react-native`, `@bugsnag/react-native` | Sentry, Bugsnag |
| `react-native-branch`, `appsflyer-react-native-plugin`, `react-native-adjust` | Branch, AppsFlyer, Adjust |
| `@intercom/intercom-react-native`, `react-native-zendesk` | Intercom, Zendesk |
| `react-native-code-push`, `appcenter-*` | Microsoft App Center (retired March 2025) |
| `@segment/analytics-react-native`, `@amplitude/analytics-react-native`, `mixpanel-react-native`, `posthog-react-native` | The analytics vendor |
| `aws-amplify`, `@aws-amplify/*` | AWS (matches neither `aws-sdk` nor `@aws-sdk`) |

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

## Open geospatial stacks - never flag

MapLibre GL, Leaflet, OpenLayers, osmdroid, and OpenStreetMap tile usage are
open source and open data. Flagging them is the geospatial version of flagging
`react`. A mapping module named after a vendor is not automatically a finding:
a repository carrying both a Mapbox adapter and an osmdroid adapter behind
one maps interface is demonstrating the abstraction this audit asks for -
classify it as an adapter set (R2a), not as two vendor couplings. Self-hosted
Nominatim, Photon, and tile servers are likewise not lock-in.

## First-party closed SaaS backends

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

## Dual-licensed (AGPL-or-commercial) libraries

`iText` (AGPL-3.0 or commercial), `JasperReports` (LGPL) and their kin ship
under an OSI-approved copyleft licence *or* a paid commercial licence. R1's
test is satisfied - an OSI-approved option exists - so these are **not
findings**.

They are also not nothing: a project that cannot comply with AGPL/GPL terms is
buying a per-seat licence from a single vendor, and that is real commercial
dependence. Record them under **Acceptable Dependencies** with a one-line
"commercial-licence coupling" note naming the library, the copyleft obligation,
and the fact that a proprietary deployment requires the paid licence. Do not
assign a severity.

**The near-miss: "free for non-commercial use" is not dual-licensed.** Verify
that the free option is actually OSI-approved before applying this exemption.
A licence limited to personal, school, evaluation, or non-profit use fails
OSI's no-discrimination-against-fields-of-endeavour criterion, so it is
proprietary and the coupling is an ordinary finding.

`Highcharts` is the canonical error here and was wrong in this table until
2026-09-16: it has **no copyleft tier at all**. Highsoft's catalogue
(https://shop.highcharts.com/license-types) offers a free personal/school/
non-profit licence or a paid commercial one, and nothing OSI-approved between
them. `Handsontable` is the same shape, and announces itself more honestly -
its bundle header states the non-commercial tier is personal/evaluation only
and adds a non-compete clause. Both are findings, severity by R3 like any
other proprietary dependency.

**Mechanical tell.** In `package.json` or a lock file, a `license` field
holding a **URL rather than an SPDX identifier** means no SPDX id exists for
that licence, which almost always means it is not OSI-approved:

```json
"license": "https://www.highcharts.com/license"
```

Neither of these libraries is reachable by the vendor patterns in
`patterns.tsv` - both were found only by Step 2's residual judgment pass, and
one of them (`Handsontable`) was committed as a minified bundle with no
manifest entry at all. When auditing a repository with a front end, read the
JS/TS manifests and any committed `static/**/vendor/` tree for licence headers,
rather than trusting the scan's silence.

## Commonly Missed Proprietary Dependencies

**This is a seed list, not an allowlist.** It exists to make SKILL.md Step 2's
residual judgment pass cheap for the usual suspects. A dependency's *absence*
from this list says nothing about it - Step 2 still requires an explicit
proprietary-or-open call on every unmatched manifest entry. When Step 2 flags
a name that no built-in scan group matches, Step 3 adds it to the scan with
`scan.sh --extra`.

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

Same rules as the table above: stated as of 2026-08, the service's licence
decides, and a name's absence from any list means nothing. Listed here are the
ones whose call is *not* obvious - especially the open-core vendors, where the
naive "hosted SaaS = lock-in" reading produces a false positive.

| Dependency / service | Licence situation | Judgment |
|---|---|---|
| Mapbox (`mapbox-gl` v2+, `@mapbox/*`) | Proprietary since GL JS v2; MapLibre GL is the BSD-3 fork of v1 | Finding. MapLibre in the same repo is not a finding |
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
| iText, JasperReports | Dual-licensed: OSI-approved copyleft (AGPL/LGPL) or paid commercial | Not a finding - record under Acceptable Dependencies with a commercial-licence note (see below) |
| Highcharts, Handsontable | Proprietary UI libraries with a free **non-commercial** tier and no OSI-approved option - commonly mistaken for the row above | Finding - severity by R3 like any proprietary dependency. Tell: lock-file `license` is a URL, not an SPDX id |

## Adding a vendor

Adding a vendor is a one-line change in `patterns.tsv`: a label, a ripgrep
regex (applied with `-i`, so never spell out case variants), and a note
carrying the judgment a bare hit cannot - what to attribute it to and what
must not be flagged. Prefer joining an existing capability group over creating
a new one, so the HIT SUMMARY stays readable, and add a case to
`tests/fixtures/scan/` so `tests/run.sh` guards it.

Some groups overlap the direct-SDK groups on purpose - `api.stripe.com`
matches Stripe and the raw-HTTP group, `llama_index.llms.openai` matches the
wrapper group and OpenAI, `@react-native-firebase/auth` matches the mobile
group and Firebase. A file under several groups still yields one finding,
naming every vendor involved.
