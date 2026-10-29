import Stripe from 'stripe';
const pi = await stripe.paymentIntents.create({ amount: 100 });
