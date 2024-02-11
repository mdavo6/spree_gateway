module Spree
  class Gateway::Airwallex < Gateway
    preference :client_id, :string
    preference :client_api_key, :string
    preference :three_d_secure, :boolean, default: false
    preference :intents, :boolean, default: true
    preference :endpoint_secret, :string

    def method_type
      'airwallex'
    end

    def provider_class
      # if get_preference(:intents)
      #   ActiveMerchant::Billing::AirwallexPaymentIntentsGateway
      # else
        ActiveMerchant::Billing::AirwallexGateway
      # end
    end

    def source_required?
      false
      # TO-DO - Should be true after intent created
    end

    def create_intent(money, card, options)
      provider.create_payment_intent(money, options)
    end

    def void(intent_id, options)
      provider.void(intent_id, options)
    end

    def purchase(money, card, options)
      byebug
      provider.purchase(money, card, options)
    end
    
    def capture(money, card, options)
      intent = get_intent(options)
      byebug
      provider.capture(money, intent, options)
    end

    def authorize(money, card, options)
      byebug
      provider.authorize(money, card, options)
    end
    
    def get_intent(options)
      payment_number = options[:order_id].partition('-').last
      payment = Spree::Payment.find_by(number: payment_number)
      payment.intent_id
    end
  end
end
