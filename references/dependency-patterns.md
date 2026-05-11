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

### Direct Configuration - VIOLATION
```javascript
// Hardcoded service configuration
const firebaseConfig = {
  apiKey: "...",
  authDomain: "...",
  projectId: "..."
};
firebase.initializeApp(firebaseConfig);
```

### Abstracted Configuration - GOOD
```javascript
// Service-agnostic configuration
const authConfig = config.get('auth');
const authService = AuthServiceFactory.create(authConfig);
```

## Common Anti-Patterns

1. **Scattered API calls**: Service calls throughout business logic
2. **Direct SDK usage**: Using vendor SDKs directly in domain code
3. **Tight coupling**: Business logic that assumes specific service behavior
4. **Missing interfaces**: No abstraction between domain and infrastructure
5. **Configuration coupling**: Service-specific config in business logic

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

### Ripgrep One-Liners

Run these in parallel from the repo root. Always include the standard skip globs.

```bash
# Standard skip set
SKIP="--glob '!node_modules' --glob '!dist' --glob '!build' --glob '!vendor' --glob '!.venv' --glob '!__pycache__' --glob '!target' --glob '!.next' --glob '!coverage'"

# Per-vendor patterns (substitute $SKIP)
rg -n "from ['\"]firebase|firebase-admin|firestore\\(|getFirestore" $SKIP
rg -n "@googlemaps|google\\.maps|googlemaps\\.Client|new google\\." $SKIP
rg -n "from ['\"]stripe['\"]|import Stripe|stripe\\.[a-zA-Z]" $SKIP
rg -n "MongoClient|mongoose|pymongo|com\\.mongodb" $SKIP
rg -n "twilio|@sendgrid|sendgrid\\.[a-zA-Z]" $SKIP
rg -n "aws-sdk|boto3|@aws-sdk" $SKIP
rg -n "@azure/|azure\\.identity|azure\\.storage" $SKIP
rg -n "@google-cloud/|google\\.cloud\\." $SKIP
rg -n "algoliasearch|@algolia/" $SKIP
rg -n "auth0|@auth0/|@okta/|okta-auth" $SKIP
rg -n "segment\\.io|mixpanel|amplitude\\.|posthog" $SKIP
rg -n "datadog|dd-trace|newrelic|@datadog/" $SKIP
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

When you see these shapes, classify the file as Adapter, Bootstrap, or Acceptable and exclude it from the violation list.
