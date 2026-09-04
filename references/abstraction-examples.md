# Abstraction Examples

## Payment Service Abstraction

### Interface Definition
```typescript
// payment.service.interface.ts
export interface PaymentService {
  createPaymentIntent(amount: number, currency: string): Promise<PaymentIntent>;
  capturePayment(paymentIntentId: string): Promise<Payment>;
  refundPayment(paymentId: string, amount?: number): Promise<Refund>;
}

export interface PaymentIntent {
  id: string;
  amount: number;
  currency: string;
  status: PaymentStatus;
}
```

### Stripe Implementation
```typescript
// stripe.payment.service.ts
import Stripe from 'stripe';
import { PaymentService, PaymentIntent } from './payment.service.interface';

export class StripePaymentService implements PaymentService {
  private stripe: Stripe;

  constructor(apiKey: string) {
    this.stripe = new Stripe(apiKey, { apiVersion: '2020-08-27' });
  }

  async createPaymentIntent(amount: number, currency: string): Promise<PaymentIntent> {
    const intent = await this.stripe.paymentIntents.create({
      amount,
      currency
    });
    
    return {
      id: intent.id,
      amount: intent.amount,
      currency: intent.currency,
      status: this.mapStatus(intent.status)
    };
  }
  
  // ... other methods
}
```

## Maps Provider Abstraction

### Interface Definition
```python
# maps_provider.py
from abc import ABC, abstractmethod
from typing import List, Tuple, Dict

class MapsProvider(ABC):
    @abstractmethod
    def geocode(self, address: str) -> Tuple[float, float]:
        """Convert address to coordinates"""
        pass
    
    @abstractmethod
    def reverse_geocode(self, lat: float, lng: float) -> str:
        """Convert coordinates to address"""
        pass
    
    @abstractmethod
    def calculate_distance(self, origin: Tuple[float, float], 
                         destination: Tuple[float, float]) -> float:
        """Calculate distance between two points"""
        pass
```

### Google Maps Implementation
```python
# google_maps_provider.py
import googlemaps
from typing import Tuple
from .maps_provider import MapsProvider

class GoogleMapsProvider(MapsProvider):
    def __init__(self, api_key: str):
        self.client = googlemaps.Client(key=api_key)
    
    def geocode(self, address: str) -> Tuple[float, float]:
        result = self.client.geocode(address)
        if result:
            location = result[0]['geometry']['location']
            return (location['lat'], location['lng'])
        raise ValueError(f"Could not geocode address: {address}")
    
    # ... other methods
```

### OpenStreetMap Implementation
```python
# osm_maps_provider.py
from geopy.geocoders import Nominatim
from geopy.distance import geodesic
from .maps_provider import MapsProvider

class OSMMapsProvider(MapsProvider):
    def __init__(self):
        self.geocoder = Nominatim(user_agent="my-app")
    
    def geocode(self, address: str) -> Tuple[float, float]:
        location = self.geocoder.geocode(address)
        if location:
            return (location.latitude, location.longitude)
        raise ValueError(f"Could not geocode address: {address}")
    
    # ... other methods
```

## Database Abstraction

### Repository Pattern
```java
// UserRepository.java
public interface UserRepository {
    User findById(String id);
    List<User> findByEmail(String email);
    User save(User user);
    void delete(String id);
}

// MongoUserRepository.java
import com.mongodb.client.MongoCollection;

public class MongoUserRepository implements UserRepository {
    private final MongoCollection<Document> collection;
    
    public MongoUserRepository(MongoDatabase database) {
        this.collection = database.getCollection("users");
    }
    
    @Override
    public User findById(String id) {
        Document doc = collection.find(eq("_id", new ObjectId(id))).first();
        return documentToUser(doc);
    }
    
    // ... other methods
}

// PostgresUserRepository.java
import java.sql.Connection;

public class PostgresUserRepository implements UserRepository {
    private final Connection connection;
    
    public PostgresUserRepository(Connection connection) {
        this.connection = connection;
    }
    
    @Override
    public User findById(String id) {
        String sql = "SELECT * FROM users WHERE id = ?";
        // ... JDBC implementation
    }
    
    // ... other methods
}
```

## Dependency Injection Configuration

### Using a DI Container
```typescript
// container.config.ts
import { Container } from 'inversify';
import { PaymentService } from './interfaces/payment.service';
import { MapsProvider } from './interfaces/maps.provider';
import { StripePaymentService } from './services/stripe.payment.service';
import { GoogleMapsProvider } from './providers/google.maps.provider';

const container = new Container();

// Bind interfaces to implementations
container.bind<PaymentService>('PaymentService')
  .to(StripePaymentService)
  .inSingletonScope();

container.bind<MapsProvider>('MapsProvider')
  .to(GoogleMapsProvider)
  .inSingletonScope();

export { container };
```

### Factory Pattern
```python
# service_factory.py
from typing import Dict, Type
from .payment_service import PaymentService
from .stripe_service import StripePaymentService
from .paypal_service import PayPalPaymentService

class ServiceFactory:
    _payment_services: Dict[str, Type[PaymentService]] = {
        'stripe': StripePaymentService,
        'paypal': PayPalPaymentService
    }
    
    @staticmethod
    def create_payment_service(provider: str, **config) -> PaymentService:
        service_class = ServiceFactory._payment_services.get(provider)
        if not service_class:
            raise ValueError(f"Unknown payment provider: {provider}")
        return service_class(**config)
```

## Testing with Abstractions

### Mock Implementation
```typescript
// mock.payment.service.ts
export class MockPaymentService implements PaymentService {
  async createPaymentIntent(amount: number, currency: string): Promise<PaymentIntent> {
    return {
      id: 'mock_pi_123',
      amount,
      currency,
      status: PaymentStatus.PENDING
    };
  }
  
  // ... other methods returning mock data
}

// payment.service.spec.ts
describe('PaymentService', () => {
  let service: PaymentService;
  
  beforeEach(() => {
    service = new MockPaymentService();
  });
  
  it('should create payment intent', async () => {
    const intent = await service.createPaymentIntent(1000, 'USD');
    expect(intent.amount).toBe(1000);
    expect(intent.currency).toBe('USD');
  });
});
```

## Configuration-Based Service Selection

### Environment-based Configuration
```javascript
// config/default.js
module.exports = {
  services: {
    payment: {
      provider: process.env.PAYMENT_PROVIDER || 'stripe',
      config: {
        apiKey: process.env.PAYMENT_API_KEY
      }
    },
    maps: {
      provider: process.env.MAPS_PROVIDER || 'google',
      config: {
        apiKey: process.env.MAPS_API_KEY
      }
    }
  }
};

// bootstrap.js
const config = require('config');
const { ServiceFactory } = require('./factories');

const paymentService = ServiceFactory.createPaymentService(
  config.get('services.payment.provider'),
  config.get('services.payment.config')
);

const mapsProvider = ServiceFactory.createMapsProvider(
  config.get('services.maps.provider'),
  config.get('services.maps.config')
);
```

---

## Good Architecture Found in the Wild

The examples above are constructed. These five are real, taken from the DPG
corpus this skill was calibrated against, and they exist for two reasons: they
show what "abstracted" looks like at production scale, and **every one of them
would be flagged as high-risk by a keyword grep**. Recognizing them is as much
a part of the audit as finding violations - a report that flags these has
failed.

Cite them when writing a "Recommended fix": pointing at a working shape from a
comparable project beats describing a pattern in the abstract.

### 1. A provider-plugin subsystem (PHP, learning platform)

```
public/ai/classes/provider.php          <- abstract port
public/ai/provider/openai/              <- adapter plugins, one per vendor
public/ai/provider/anthropic/
public/ai/provider/gemini/
public/ai/provider/azureai/
public/ai/provider/awsbedrock/
public/ai/provider/deepseek/
public/ai/provider/ollama/              <- self-hosted, open-weight
```

Why it passes: the domain talks to `provider`, never to a vendor SDK. Seven
vendor names appear in the tree, which is exactly why a naive scan calls this
the most locked-in repository in the corpus - while it is the least. The
`ollama` plugin is the proof: the subsystem already runs against a self-hosted
backend, so the swap cost is installing a plugin.

Report as `[OK]`, and name it in Acceptable Dependencies as a provider-plugin
architecture.

### 2. A port module with a proprietary and an open adapter (Kotlin, Android)

```
maps/                <- port: MapFragment, MapConfigurator, MapFragmentFactory
google-maps/         <- adapter: Google Maps
osmdroid/            <- adapter: OpenStreetMap
```

Why it passes: the app depends on `maps/`; the vendor lives in a sibling module
that nothing else imports (R2a satisfied at module granularity). The presence
of an *open* adapter beside the proprietary one is empirical proof the
abstraction holds - the project has already done the swap once.

The Mapbox or Google Maps hits inside `google-maps/` are adapter-internal and
are not findings.

### 3. api / impl sibling modules with build-variant gating (Kotlin, Android)

```
libraries/pushproviders/api/         <- port
libraries/pushproviders/firebase/    <- FCM adapter      (gplay flavour)
libraries/pushproviders/unifiedpush/ <- open adapter      (fdroid flavour)
libraries/pushproviders/test/        <- test double
```

Why it passes: the `api` / adapter / `test` split is the convention described
in `classification-rules.md` R2b, and the F-Droid build ships with no Firebase
at all. Two rules apply together - R2b (layout signals an adapter set) and R3's
build-variant modifier (a vendor confined to a non-default flavour is
contained). Say which flavour ships to users.

### 4. An env-switched storage factory (JavaScript, Node)

```js
// src/configs/cloud-service.js - the ONLY place a storage vendor is chosen
const cloudService = require('client-cloud-services')

let cloudConfig = {
  provider: process.env.CLOUD_STORAGE_PROVIDER,   // aws | gcp | azure | oci ...
  identity: process.env.CLOUD_STORAGE_ACCOUNTNAME,
  credential: process.env.CLOUD_STORAGE_SECRET,
  endpoint: process.env.CLOUD_ENDPOINT || null,   // self-hosted S3-compatible
}
exports.cloudClient = cloudService.init(cloudConfig)
```

Why it passes: domain code imports `cloudClient`, never a cloud SDK. The vendor
is a deployment variable, and the `endpoint` override means the same code runs
against MinIO. This is the cheapest abstraction in the list - a single
composition-root module - and the one most worth recommending to projects that
have none.

### 5. An injected RPC provider (TypeScript, blockchain)

```ts
// The domain takes an abstract provider; nothing hardcodes a vendor endpoint.
export async function verifyDocument(provider: ethers.Provider, id: string) { ... }
```

Why it passes: hosted RPC vendors (Infura, Alchemy) are proprietary, but here
the provider is a constructor argument and the RPC URL is configuration. The
switching cost is a config value, not a code change. Contrast with a hardcoded
`https://mainnet.infura.io/v3/<key>` in a use case, which is a finding.

### What these have in common

1. **One place names the vendor** - a plugin directory, a sibling module, a
   config factory, an injected argument.
2. **The port is named after the capability**, not the vendor (`provider`,
   `MapFragment`, `pushproviders/api`, `cloudClient`).
3. **A second implementation exists** - often an open or self-hosted one. That
   is the strongest evidence an abstraction is real rather than aspirational,
   and it is worth saying so explicitly in the report.
