require 'stripe'

class Billing
  def charge
    Stripe::Charge.create(amount: 100)
  end
end
