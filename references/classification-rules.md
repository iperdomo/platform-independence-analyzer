# Classification Rules

The authoritative rulebook for classifying a vendor-dependency hit: what counts
as a finding, what role a file plays, what severity it earns, and what must not
be flagged.

**Both tiers of the audit cite this file.** Tier 1 (the mechanical scan) applies
only the *name/path heuristics* in R2 to produce tentative labels. Tier 2 (the
verification pass) applies every rule here in full. A Tier 1 label is never
final.

This file is self-contained on purpose: a fresh-context verifier should be able
to work from this document plus `dependency-patterns.md` alone, without reading
the skill's workflow instructions.

---

## R1. Scope - what counts as a finding

- **Platform independence**: domain or business code makes no direct API call
  into a proprietary SDK or service. All proprietary calls flow through an
  abstraction: adapter, port, repository, provider, gateway.
- **Direct dependency (violation)**: a domain or business-layer file imports a
  vendor SDK or hits a vendor-specific URL.
- **Indirect dependency (acceptable)**: domain code uses an interface or
  abstract type. Only a designated adapter or repository file imports the vendor
  SDK.

**This audit assesses platform independence (vendor lock-in risk), not
architectural quality or robustness.** Direct dependencies on OSI-approved
open-source libraries, modules, or services are **acceptable** and must not be
flagged, even when imported straight from domain code with no abstraction layer.
Whether such code *should* be abstracted for testability, modularity, or
clean-architecture reasons is out of scope. A library qualifies if it is
released under an [OSI-approved license](https://opensource.org/licenses) (MIT,
Apache-2.0, BSD, GPL, MPL, etc.); when a license is unclear, treat it as
proprietary and flag it. Only proprietary, closed-source, or vendor-controlled
SaaS dependencies count as findings.

**The service's license matters, not the client library's.** Judge lock-in by
the backing service or protocol a dependency binds you to, not by the license of
the SDK on npm/PyPI. Example: `mongoose` is MIT-licensed, but it exists to talk
to MongoDB, whose server is SSPL (not OSI-approved) - so a `mongoose` coupling
is a finding. Conversely, an MIT-licensed Postgres driver binds you only to an
open protocol, so it is Acceptable. When a permissively licensed client is just
a wrapper around a proprietary SaaS, flag it.

**Out of scope: infrastructure and deployment coupling.** `serverless.yml`,
Helm charts and values, `docker-compose*.yml`, CI workflows, `Procfile`,
`netlify.toml`, `firebase.json`, `app.yaml` and their kin are **not finding
sources**. This audit is about the code's coupling to proprietary services, not
about where the code is deployed - a project can move clouds without touching a
line of business logic, which is exactly the property this report measures.

Read those files anyway, as evidence: resolving an endpoint (R5), confirming
which vendor products are enabled, and catching dynamic config that overrides
static config. When a repository's *only* vendor coupling lives in deployment
files - a compose-only or Helm-only project is the common case - the correct
result is **no code-level findings**. Say that explicitly in the Executive
Summary and name the deployment coupling in one informational sentence, so the
clean result reads as a deliberate scope decision rather than an audit that did
not look.

**Licenses are facts to look up, not recall.** Vendor relicensing moves faster
than any model's training data, and a confidently remembered license is the most
likely way a correct finding gets wrongly overturned. The license table in
`dependency-patterns.md` ("Commonly Missed Proprietary Dependencies") is the
authority here; it is dated, and it covers the vendors whose licenses actually
changed - Elastic, Sentry, Terraform, Confluent, MongoDB, Redis. If a finding
cites a license basis, check it against that table rather than memory. If
neither settles it, keep the finding and note the ambiguity.

**Dual-licensed libraries (AGPL-or-commercial)** - iText, JasperReports,
Highcharts and their kin - satisfy this test: an OSI-approved option exists, so
they are **not findings**. Record them under Acceptable Dependencies with a
one-line note that a closed-source deployment requires the paid licence. That
is commercial dependence worth seeing, but it is not the vendor-controlled
lock-in this audit measures.

The whole audit is the question "if we had to replace vendor X tomorrow, which
non-adapter files would change?" - where "vendor X" is a *proprietary*
dependency. Open-source dependencies can always be forked, self-hosted, or
replaced without vendor cooperation, so they do not create lock-in. Every
non-adapter file touching a proprietary SDK is a finding.

---

## R2. Role - what this file is doing with the vendor

For each file with at least one hit, assign a role. **Tier 1 uses the Heuristic
column only**: apply the name/path signal and stop - no reading call sites, no
following imports, no sole-referencer check. When the heuristics are ambiguous,
default to the more severe role (Violation) and let Tier 2 downgrade it.

| Role | Heuristic | Treat as |
|---|---|---|
| Adapter / Provider / Repository / Gateway | File implements an interface or abstract class AND its name or directory marks it as the vendor's wrapper (e.g. `stripe-payment.adapter.ts`, `adapters/`, `infrastructure/`, `repositories/`). | Acceptable |
| Composition root / Bootstrap | Wires services into a DI container or factory at startup (e.g. `container.ts`, `main.py`, `bootstrap.js`, `wire.go`). | Acceptable |
| Configuration | Reads vendor config from env vars; does not invoke the SDK. | Acceptable |
| Domain or business logic with vendor call | Lives under `domain/`, `core/`, `usecases/`, `controllers/`, `handlers/`, `app/`, etc. and imports the SDK directly. | Violation |
| Directory named `services/` | **Ambiguous - read R2b before labelling.** `services/` means "business services" in some layouts and "adapters to external services" in others. | Decide from the neighbours, not the name |
| Test using real SDK | Integration test against live vendor. | Low - flag |
| Test mocking the SDK directly | Unit test mocks the vendor instead of an interface. | Medium - coupling leaks into tests |

**React Native / mobile layouts.** RN apps rarely use `domain/` or `usecases/`.
Read the equivalents: `screens/`, `components/`, `hooks/`, `navigation/`,
`app/` (Expo Router) are the domain layer - a `@react-native-firebase` import
there is a Violation. `src/services/`, `api/`, `data/`, `repositories/`, or
`lib/<vendor>*.ts` get the usual adapter treatment. Two mobile-only roles:

| Role | Heuristic | Treat as |
|---|---|---|
| Native wiring | `ios/Podfile`, `ios/AppDelegate.*`, `android/app/build.gradle`, `android/**/MainApplication.*`, `app.json` / `app.config.*`, `GoogleService-Info.plist`, `google-services.json`. Declares or initializes the SDK at app startup. | Bootstrap - Acceptable; use it for *coverage* (which vendor products are enabled), not severity |
| Generated native artifact | `Pods/`, `*.pbxproj`, `.expo/`, `android/.gradle/`. | Not evidence - the scanner already excludes these; if one appears, ignore it |

### R2a. The adapter test (Tier 2 only)

A file is a *real* adapter only if **both** conditions hold:

- **(a)** it implements an interface or abstract class for that capability, and
- **(b)** it is the *only* place that vendor SDK is referenced for that
  capability.

A file named `*-adapter.*` that still has callers importing the SDK elsewhere is
not a real adapter. Confirming (b) requires a repo-wide grep for the SDK import.
In Tier 1, a path/name that looks like an adapter earns a *tentative* Acceptable
label only.

Note on (b): the check is written "for that capability", but the grep that
settles it searches for the *SDK import*. Those diverge when the same vendor
capability is also reached without the SDK - a raw HTTP call to the vendor's
API, for instance. When that happens, the adapter itself can still be
Acceptable; the bypass is its own separate finding. Do not fail an otherwise
clean adapter because of a bypass elsewhere - report both facts.

### R2b. Layout conventions that signal an adapter set

A path is evidence, not proof, and the same directory name means opposite
things in different ecosystems. Before calling a `services/` hit a violation,
look at what sits *beside* it. These layouts are adapter sets, and flagging
them is the most common false positive this audit can produce:

- **`api` / `impl` / `noop` sibling modules.** A capability split into
  `<capability>/api` (interfaces), `<capability>/impl` or one module per vendor
  (`<capability>/posthog`, `<capability>/sentry`), and `<capability>/noop` (a
  do-nothing build for privacy-respecting or offline variants) is a textbook
  port-and-adapters set. The vendor module is the adapter; the `api` module is
  the port. Real example: an Android client with
  `services/analyticsproviders/{api,posthog,sentry}`.
- **One directory per provider under a shared port.** `provider/openai`,
  `provider/anthropic`, `provider/ollama` next to an abstract `provider`
  class - the presence of *several* providers is itself the proof that the
  abstraction works.
- **Protocol + mock pairs.** In Swift or Kotlin, a `FooServiceProtocol` (or
  interface) with both a vendor implementation and a `MockFooService` in tests
  means the domain depends on the protocol, not the vendor.
- **Native Android package-by-layer.** `activities/`, `fragments/`,
  `widgets/`, `adapters/` (RecyclerView adapters!) are the *presentation*
  layer, not the ports-and-adapters kind. A vendor SDK imported into an
  `Activity` is a Violation; a directory literally named `adapters/` in an
  Android app is usually about list rendering and is not an abstraction at all.
  Read the file, not the folder.
- **A `services/` directory whose files each wrap one external system**
  (`stripe.service.ts`, `sendgrid.service.ts`, each implementing an interface)
  is an adapter set. A `services/` directory holding `OrderService` and
  `BillingService` that call vendors inline is the domain layer.

When the layout says adapter and the name says domain, the layout wins - then
confirm with R2a's sole-referencer check.

---

## R3. Severity

Pick the severity that matches the role from R2. In Tier 1, mark it as a guess
by appending a `?` in the finding heading (e.g. `[High?]`); Tier 2 removes the
`?` when it confirms, or changes the level when it adjusts.

- **Critical**: vendor SDK called from the domain layer with no interface
  anywhere; multiple call sites.
- **High**: vendor SDK called from a service layer that lacks an interface;
  concentrated in one or two files.
- **Medium**: an interface exists but leaks vendor types through its public
  surface (e.g. a method returns `Stripe.PaymentIntent`), or unit tests mock the
  SDK directly.
- **Low**: scripts, CLIs, migrations, or integration tests that import the SDK
  directly while production code is properly abstracted.

**Build-variant containment (severity modifier).** A vendor confined to a
non-default build variant - a `gplay` flavour that ships Firebase Cloud
Messaging while the `fdroid` flavour ships a different push provider, a
`debug`-only analytics SDK - is architecturally contained even when no
interface exists: the project already demonstrates it can build and ship
without that vendor. A flat grep sees no difference between a flavour-gated
import and an unconditional one, so check the build files.

Lower the severity by one level when the vendor appears **only** in
non-default variant sources (`src/gplay/`, `src/<flavor>/`, a
`<flavor>Implementation` dependency, a variant-gated plugin), and say which
variant in the finding. Do not lower it when the gated variant is the one
actually shipped to users - name which variant that is.

**Ambiguity discount.** When a coupling is real but its *magnitude* depends on
deployment config the repo does not settle - the indeterminate LLM `base_url` of
R4 being the standard case - cap the severity at **Medium**, or **Low** when
production code is otherwise abstracted, and state the unresolved question in
the finding. Unresolved ambiguity lowers the level; it never removes the
finding.

---

## R4. Acceptable patterns - do not flag these

- **AWS S3** specifically - open S3 protocol, swappable with MinIO, Ceph,
  Garage. Other AWS services remain in scope.
- **Standard protocols**: HTTP, HTTPS, SMTP, IMAP, OAuth, OIDC, gRPC,
  WebSockets, MQTT.
- **OSI-approved open-source datastores**: PostgreSQL, MySQL, MariaDB, SQLite,
  Cassandra, Redis, Valkey. (Redis 8+ returned to AGPLv3 in 2025, which is
  OSI-approved; the 2024 SSPL-only versions are the exception. Valkey, the
  BSD-licensed fork, is always fine.)
- **A vendor SDK imported only inside its dedicated adapter file** - see R2a.
- **Type-only imports** (`import type ...`) of vendor types when domain types
  are used everywhere else. If a vendor type leaks through a public interface,
  downgrade to Medium rather than ignore.
- **A client pointed at a self-hosted instance of a hostable service.** This
  is the general form of the AWS S3 `endpoint_url` case, and it is not
  LLM-specific. When a vendor's client library is configured with a
  `base_url` / `endpoint` / `host` that targets an instance the project can run
  itself, the lock-in is materially reduced: the same code runs against a
  backend nobody can withhold. It applies to every client of a hostable
  service, including:

  | Client | Self-hostable target that reduces lock-in |
  |---|---|
  | `openai` and OpenAI-compatible SDKs | vLLM, Ollama, LiteLLM, LocalAI, TGI |
  | `@sentry/*`, `sentry-sdk` | a self-hosted Sentry (check the DSN host) |
  | `posthog-*`, Matomo | a self-hosted instance |
  | `@supabase/*` | a self-hosted Supabase, or plain PostgREST + Postgres - a repo using the Supabase client purely as a PostgREST client against its own database is NOT locked into Supabase, and calling it "BaaS lock-in" from the package name alone is a false positive |
  | `elasticsearch` / `@elastic/*` | a self-hosted cluster, or OpenSearch |
  | `boto3` / `@aws-sdk/client-s3` | MinIO, Ceph, Garage |
  | `langfuse`, `livekit`, `pyvespa`, `clearml` | their self-hosted open-core servers |

  Resolve the endpoint before applying this (R5 lists where to look). The
  exception does **not** apply when:
  - there is no endpoint override at all (the SDK hits the vendor's default
    hosted service - a finding);
  - the endpoint points at another proprietary SaaS (Azure OpenAI, Groq,
    Together, Perplexity, Elastic Cloud, Sentry's own sentry.io on a paid
    plan) - still a finding, and re-attribute it to that vendor;
  - the call uses a cloud-proprietary path such as `AnthropicBedrock` /
    `AnthropicVertex`;
  - **the endpoint is indeterminate** - a bare `os.environ["LLM_BASE_URL"]`
    with no default could be vLLM, Groq, or the vendor's own API depending on
    deployment. Try to resolve it; if it stays unknowable, keep the finding at
    **Low or Medium with an ambiguity note**. Never reject on an unresolvable
    variable - the exception rewards a codebase that *shows* its endpoint is
    open, not one that hides it behind a variable.

- **React Native, the Expo SDK, and open RN modules** - `react-native`,
  `expo` and its OS-API wrappers (`expo-camera`, `expo-file-system`),
  `react-navigation`, `react-native-reanimated`, `react-native-mmkv`,
  `@react-native-async-storage/async-storage` are MIT. They are frameworks and
  libraries, not services, so R1's open-source rule applies: not findings, even
  imported straight into a screen. Only the proprietary *service* behind a
  binding is (`@react-native-firebase/*` -> Firebase, `react-native-purchases`
  -> RevenueCat).

- **Platform rails** - proprietary services that come with the platform you
  ship on, and that no abstraction removes while you ship there. Report each
  one, say plainly that an adapter contains the blast radius without removing
  the coupling, and do not inflate the severity for something the project
  cannot architect away:
  - **App Store / Play billing** (`react-native-iap`, `expo-in-app-purchases`,
    StoreKit, Play Billing).
  - **OS push transports** - APNs and FCM are the only ways to reach an iOS or
    Android device. The transport is platform rails; a push *vendor* layered on
    top (OneSignal, Braze, Airship) is an ordinary finding, because that one is
    swappable. Note which of the two a repository has: an app talking straight
    to FCM is less locked in than one routing through a push SaaS.
  - **Platform sign-in SDKs** - the Facebook Login SDK, Google Sign-In SDK and
    Sign in with Apple bind you to that identity provider through its own SDK
    and flow: findings, at platform-rails weight. The distinguishing test is
    the protocol, not the provider - code speaking plain **OIDC/OAuth** against
    a configurable issuer is Acceptable under "standard protocols" above, even
    when the issuer happens to be Google, because swapping the issuer is
    configuration.

**Mobile bindings (`@react-native-firebase/*`, `react-native-purchases`, ...).**
Same rule as the LLM wrappers below: the MIT binding is never the finding -
attribute it to the service it reaches and name that service in the finding
title. Native declarations (`Podfile`, `build.gradle`) are Bootstrap per R2; the
severity comes from what the JS/Swift/Kotlin code does. See "Mobile Binding
Attribution" in `dependency-patterns.md`.

**LLM wrapper libraries (LangChain, LlamaIndex, Vercel AI SDK, LiteLLM).** These
are MIT/Apache-licensed, so the wrapper itself is never the finding - attribute
it to the proprietary model API it binds to (`from langchain_openai import
ChatOpenAI` is an *OpenAI* finding). But a provider-agnostic wrapper can itself
*be* the abstraction: code written against a generic chat-model type with the
concrete provider chosen at composition time, or a LiteLLM call whose model
string comes from config, is doing an adapter's job and lock-in is reduced. Code
importing `ChatOpenAI` straight into a use case, or hardcoding a proprietary
model string in domain code, is not. Tier 1 surfaces the import; Tier 2 decides
which shape it is. See "LLM Wrapper Attribution" in `dependency-patterns.md`.

**When in doubt, flag and let the user decide; document the ambiguity in the
finding.**

---

## R4a. Verdict vocabulary: REJECTED vs ADJUSTED [OK]

These two both mean "not a violation" and both stay out of the severity counts,
but they say different things and must not be used interchangeably:

- **REJECTED** - the claim was *wrong*. The cited lines are not real vendor
  usage at all: a comment, a doc, a fixture string, a stale TODO. Heading
  becomes `[N/A]`.
- **ADJUSTED [OK]** - the usage is *real* but *acceptable* under R4. A genuine
  adapter that passes R2a, an S3-only boto3 call, a `base_url` resolving to a
  self-hosted runtime. Heading becomes `[OK]`.

A real adapter is `ADJUSTED ... [OK]`, never `REJECTED` - the Stripe SDK import
is genuinely there, and the File Index should show it as a checked-and-cleared
adapter rather than implying Tier 1 hallucinated it.

---

## R4b. Self-hosted but coupled services

Some dependencies are not proprietary at all and still shape the architecture:
an Ollama runtime at `localhost:11434`, an Asterisk PBX, a PostgREST instance,
a self-hosted Sentry, a SIP/STUN server named in `.env.example`. Today these
are invisible to the audit - no vendor pattern matches them and no rule tells
you what to do when one does.

They are **not findings**: nobody can withhold, price, or discontinue software
the project runs itself. But they are worth **one informational line** in
Acceptable Dependencies, because replacing them is still real work and a reader
comparing two codebases should see them. Say what the service is, that it is
self-hosted or self-hostable, and where it is configured.

The same line serves the case where a *proprietary* client is pointed at a
self-hosted instance (R4's table): record the coupling, note that the endpoint
resolves to something the project controls, and assign no severity.

## R4c. Free hosted data APIs

A public HTTP API with no token and an open-data licence - Open-Meteo,
Nominatim's public instance, GeoJS, the Wayback Machine - is a **single-vendor
dependency without lock-in economics**: no account, no contract, and usually a
self-hostable or substitutable backend. Mention it informationally; do not
raise a finding.

The line moves as soon as the API is **token-gated or paid**: an API key in
the config, a quota, or a commercial licence (ElectricityMaps is the corpus
example) makes it an ordinary proprietary-service finding, judged like any
other SaaS. The question is not "is it free today" but "can the vendor cut this
off or charge for it".

## R5. Resolving a service endpoint

R4's self-hosted exception is only as good as the endpoint you can actually
resolve. This rule applies to **any** client of a hostable service - an LLM
runtime, Sentry, PostHog, Supabase/PostgREST, Elasticsearch, S3 - not just LLM
SDKs.

When a `base_url` / `baseURL` / `endpoint` / DSN reads from an environment
variable, the endpoint is **not** knowable from that line. Chase the actual
value before deciding, stopping at the first hit:

1. A literal default in the call itself (`os.environ.get(..., "http://...")`,
   `process.env.X ?? "http://..."`).
2. `.env.example`, `.env.sample`, `.env.defaults`, `.env.template` - a variable
   listed there with an **empty** value resolves nothing, keep looking.
3. `docker-compose*.yml` (an ollama/vllm/litellm service next to the app is
   strong evidence), Helm `values.yaml`, k8s manifests, Terraform.
4. Config modules with a fallback constant, CI workflow env blocks, README or
   deployment docs.

If the value resolves, judge it under R4. If it does **not** resolve, the
finding survives as `ADJUSTED (endpoint indeterminate)` at Low or Medium with
the ambiguity spelled out - never `REJECTED`. An unresolvable variable is
missing evidence, not evidence of an open endpoint.

A useful secondary signal: a hardcoded proprietary model name (`gpt-4o`,
`claude-sonnet-4`) alongside an unresolved `base_url` points at the vendor's
hosted API, since no open-weight runtime serves those models. The equivalent
for other services: a DSN whose host is `*.ingest.sentry.io`, a Supabase URL
ending in `.supabase.co`, an Elastic Cloud ID - each pins the hosted tier.

### R5a. Endpoints resolved at runtime, not in source

Some codebases make the static ladder unanswerable *by design*, and that is a
different verdict from "indeterminate variable". The shape to recognize is a
**provider registry**: one client class instantiated repeatedly with a
different endpoint per provider, where the endpoints come from a database
table, an admin UI, a plugin registry, or another service's API
(`modal.Function.get_web_url()` returning the URL of a self-hosted vLLM
deployment, for instance).

Do not force this into a single verdict. Instead:

1. **Describe the registry**: where the provider list lives (table, config
   module, plugin directory), and where the endpoint value comes from.
2. **Judge each leg separately.** A registry containing OpenAI, Anthropic, a
   self-hosted vLLM and a hosted Groq deployment is one finding per
   *proprietary* leg, not one finding for the registry. Legs that resolve to
   self-hosted runtimes fall under R4.
3. **Credit the indirection.** A registry with a stable internal interface is
   doing an adapter's job: the swap cost is a row, not a rewrite. That is a
   severity reduction (often to Low, sometimes `[OK]`), even though several
   proprietary providers are reachable.
4. Verdict wording: `ADJUSTED (endpoint resolved at runtime - provider
   registry)`, with the per-leg judgment in the verification note.

The distinction that matters: an unresolvable *variable* is missing evidence
(keep the finding, Low/Medium, ambiguity noted); a *registry* is present
evidence of an abstraction (describe it, judge the legs).

---

## R6. What real vendor usage looks like

Three shapes all count as real usage. Do not dismiss a finding merely because it
is not the first one:

- **(a)** a vendor SDK call or import;
- **(b)** a request to a vendor HTTP endpoint with no SDK involved
  (`fetch`/`httpx`/`axios`/`requests` against `api.stripe.com`,
  `api.openai.com`, `*.googleapis.com`, ...). A URL in a config constant or env
  default that is then used to build requests counts;
- **(c)** an LLM wrapper import (`langchain_openai`, `@ai-sdk/*`,
  `llama_index.llms.*`, `litellm`) that reaches a proprietary model API
  transitively.

Cited lines that turn out to be a comment, a doc, a test fixture string, or
otherwise not real usage are false positives.

---

## R7. Hardcoded credentials next to a vendor hit

While reading call sites you will find API keys, tokens and project IDs
committed in source: a translation-service token in a `Constants.h`, a vision
API key in a Dart service class, an analytics environment ID in a layout
component, a tracking ID in `index.html`.

**This is never the finding.** Credential hygiene is not platform
independence, and this audit does not become a secrets scan. But it costs one
sentence to say, and it is high-value information the reader gets nowhere else
in the report:

- add it as a single clause in the finding that already cites that file
  ("...and the API key is hardcoded at `lib/roboflow_service.dart:14`");
- never create a finding for it, never assign it a severity, never let it
  change the severity of the coupling;
- do not quote the credential value itself - cite `path:line`.

If a repository is riddled with them, one line in the Architecture
Recommendations ("several vendor credentials are committed in source; rotate
and move them to configuration") is the right amount of attention.

---

## R8. Findings inherited from an upstream fork

Many deployments are forks of an upstream platform: a Dolibarr-based ERP, an
ODK-based data-collection app, a Coqui-based speech stack. Vendor couplings
inside inherited upstream code are **real for the deployment** - if the vendor
disappears, the deployment breaks - but they are not the same actionable item
as coupling the project's own team wrote.

Report them, and attribute them:

- keep the finding (the lock-in exists regardless of who wrote the line);
- mark it `inherited from upstream <project>` in the finding, and prefer one
  aggregate finding per upstream vendor over dozens of per-file findings
  (`triage-and-noise.md` T5);
- adjust the *recommendation*, not the severity: for inherited code the
  realistic advice is usually "raise it upstream, or isolate it behind a
  project-owned wrapper", not "refactor the vendor call";
- when the project's own code adds a *new* vendor coupling on top of the
  upstream base, say so explicitly - that is the part the team controls, and
  it is what the reader most needs separated out.

Detect the situation from a `README` naming the upstream, a fork marker in the
repository metadata, an upstream `CHANGELOG`, or a directory tree that matches
a known project's layout. When unsure whether code is inherited, say so rather
than guessing.
