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
