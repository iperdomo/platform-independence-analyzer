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

**Licenses are facts to look up, not recall.** Vendor relicensing moves faster
than any model's training data, and a confidently remembered license is the most
likely way a correct finding gets wrongly overturned. The license table in
`dependency-patterns.md` ("Commonly Missed Proprietary Dependencies") is the
authority here; it is dated, and it covers the vendors whose licenses actually
changed - Elastic, Sentry, Terraform, Confluent, MongoDB, Redis. If a finding
cites a license basis, check it against that table rather than memory. If
neither settles it, keep the finding and note the ambiguity.

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
| Domain or business logic with vendor call | Lives under `domain/`, `core/`, `services/`, `usecases/`, `controllers/`, `handlers/`, `app/`, etc. and imports the SDK directly. | Violation |
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
- **LLM SDK pointed at a self-hostable, OpenAI-compatible endpoint** - an
  `openai`/LLM client configured with a `base_url`/`baseURL` (or Python
  `base_url`) that targets a self-hostable, open-weight runtime (vLLM, Ollama,
  LiteLLM, LocalAI, TGI) is like AWS S3 with an `endpoint_url`: the same code
  runs against a swappable open backend, so lock-in is reduced. This exception
  applies *only* when the endpoint is self-hostable/open. It does **not** apply
  when:
  - there is no `base_url` override (the SDK hits the vendor's default hosted
    API - a finding);
  - the `base_url` points at another proprietary SaaS (Azure OpenAI, Groq,
    Together, Perplexity) - still a finding, and re-attribute it to that vendor;
  - the call uses a cloud-proprietary path such as `AnthropicBedrock` /
    `AnthropicVertex` - still a finding;
  - **the endpoint is indeterminate** - a bare `os.environ["LLM_BASE_URL"]` with
    no default could be vLLM, Groq, or the vendor's own API depending on
    deployment. Try to resolve it (R5 lists where to look); if it stays
    unknowable, keep the finding at **Low or Medium with an ambiguity note**.
    Never reject on an unresolvable variable - the exception rewards a codebase
    that *shows* its endpoint is open, not one that hides it behind a variable.

- **React Native, the Expo SDK, and open RN modules** - `react-native`,
  `expo` and its OS-API wrappers (`expo-camera`, `expo-file-system`),
  `react-navigation`, `react-native-reanimated`, `react-native-mmkv`,
  `@react-native-async-storage/async-storage` are MIT. They are frameworks and
  libraries, not services, so R1's open-source rule applies: not findings, even
  imported straight into a screen. Only the proprietary *service* behind a
  binding is (`@react-native-firebase/*` -> Firebase, `react-native-purchases`
  -> RevenueCat). Exception worth naming rather than flagging silently: App
  Store / Play billing (`react-native-iap`, `expo-in-app-purchases`) is real
  platform lock-in that no abstraction removes while you ship through those
  stores - report it, and say so.

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

- **REJECTED** — the claim was *wrong*. The cited lines are not real vendor
  usage at all: a comment, a doc, a fixture string, a stale TODO. Heading
  becomes `[N/A]`.
- **ADJUSTED [OK]** — the usage is *real* but *acceptable* under R4. A genuine
  adapter that passes R2a, an S3-only boto3 call, a `base_url` resolving to a
  self-hosted runtime. Heading becomes `[OK]`.

A real adapter is `ADJUSTED ... [OK]`, never `REJECTED` — the Stripe SDK import
is genuinely there, and the File Index should show it as a checked-and-cleared
adapter rather than implying Tier 1 hallucinated it.

---

## R5. Resolving an env-var LLM endpoint

When a `base_url`/`baseURL` override reads from an environment variable, the
endpoint is **not** knowable from that line. Chase the actual value before
deciding, stopping at the first hit:

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
hosted API, since no open-weight runtime serves those models.

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
