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

Classify such a site by the file's role (Step 4): a call like
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
libraries, or config that merely names a vendor. See the SKILL.md scope
section.

## Detection Keywords

### High-Risk Keywords
- `firebase`, `firestore`, `firebase-admin`
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

Patterns use `-i` (case-insensitive, so `Twilio`/`SENDGRID` match) and word
boundaries (`\b...\b`) where a bare vendor name would otherwise match
substrings and prose. Restrict to source globs (e.g. `--glob '*.ts'`) when a
pattern is still too noisy.

```bash
# Per-vendor patterns. Add the exclusions above as needed, e.g.:
#   rg -in "\btwilio\b" --glob '!**/*.md' --glob '!**/vendor/**'
rg -in "from ['\"]firebase|firebase-admin|firestore\\(|getFirestore"
rg -in "@googlemaps|google\\.maps|googlemaps\\.Client|new google\\."
rg -in "from ['\"]stripe['\"]|import Stripe|\\bstripe\\.[a-zA-Z]"
rg -in "\bMongoClient\b|\bmongoose\b|\bpymongo\b|com\\.mongodb"
rg -in "\btwilio\b|@sendgrid|\bsendgrid\\.[a-zA-Z]"
rg -in "aws-sdk|\bboto3\b|@aws-sdk"
rg -in "@azure/|azure\\.identity|azure\\.storage"
rg -in "@google-cloud/|google\\.cloud\\."
rg -in "algoliasearch|@algolia/"
rg -in "\bauth0\b|@auth0/|@okta/|okta-auth"
rg -in "segment\\.io|\bmixpanel\b|\bamplitude\\.|\bposthog\b"
rg -in "\bdatadog\b|dd-trace|\bnewrelic\b|@datadog/"
# LLM/AI SaaS SDKs (mirror of scripts/scan.sh)
rg -in "from ['\"]?openai\b|require\\(['\"]openai|\bimport openai\b|\bOpenAI\\(|\bAzureOpenAI\\(|\bopenai\\.[a-zA-Z]"
rg -in "@anthropic-ai/|from ['\"]?anthropic\b|\bimport anthropic\b|\bAnthropic\\(|AnthropicBedrock|AnthropicVertex|\banthropic\\.[a-zA-Z]"
rg -in "@google/generative-ai|@google/genai|google-genai|google[-.]generativeai|google import genai|\bGoogleGenerativeAI\b|\bgenai\\.[a-zA-Z]"
rg -in "cohere-ai|from ['\"]?cohere\b|\bimport cohere\b|\bCohereClient\b|\bcohere\\.[a-zA-Z]"
rg -in "@mistralai/|from ['\"]?mistralai\b|\bimport mistralai\b|\bMistralClient\b|\bMistral\\(|\bmistralai\\.[a-zA-Z]"
```

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
# LLM SDK pointed at a self-hostable, OpenAI-compatible endpoint via base_url —
# reduced lock-in (like S3's endpoint_url). The same code runs against vLLM,
# Ollama, LiteLLM, LocalAI, or TGI, so the OpenAI service is swappable.
from openai import OpenAI
client = OpenAI(base_url=os.environ["LLM_BASE_URL"], api_key=os.environ["LLM_KEY"])
```

Caveat for the LLM case: a `base_url`/`baseURL` override is acceptable only when it
points at a self-hostable / open-weight runtime. If it points at another
proprietary SaaS (Azure OpenAI, Groq, Together, Perplexity) or the call uses
Bedrock/Vertex, it is still a finding — re-attribute it to that vendor. With no
override at all, treat it as the vendor's default hosted API (a finding).

When you see these shapes, classify the file as Adapter, Bootstrap, or Acceptable and exclude it from the violation list.
