module Spree
  module Api
    module V2
      module Storefront
        class WebhooksController < ::Spree::Api::V2::BaseController

          def stripe
            require 'stripe'
            Stripe.api_key = ::Spree::Gateway::StripeElementsGateway&.active.first.get_preference(:secret_key)
            endpoint_secret = ::Spree::Gateway::StripeElementsGateway&.active.first.get_preference(:endpoint_secret)

            payload = request.body.read
            event = nil

            begin
              event = Stripe::Event.construct_from(
                JSON.parse(payload, symbolize_names: true)
              )
            rescue JSON::ParserError => e
              # Invalid payload
              puts "Webhook error while parsing basic request. #{e.message})"
              status 400
              return
            end
            # Check if webhook signing is configured.
            if endpoint_secret
              # Retrieve the event by verifying the signature using the raw body and secret.
              signature = request.env['HTTP_STRIPE_SIGNATURE'];
              begin
                event = Stripe::Webhook.construct_event(
                  payload, signature, endpoint_secret
                )
              rescue Stripe::SignatureVerificationError
                puts "Webhook signature verification failed. #{err.message})"
                status 400
              end
            end

            # Handle the event
            case event.type
            when 'payment_intent.succeeded'
              payment_intent = event.data.object # contains a Stripe::PaymentIntent
              puts "Payment for #{payment_intent['amount']} succeeded."

              # Find payment details (from stripe payment element) and payment in spree
              stripe_payment_method = Stripe::PaymentMethod.retrieve(payment_intent[:payment_method])
              payment = Spree::Payment.find_by(intent_id: payment_intent['id'])

              if payment
                payment_method = payment.payment_method
                # Create source using payment details from stripe payment element
                if payment.source.blank? && payment_method.try(:payment_source_class)
                  payment.source = payment_method.payment_source_class.create!({
                    gateway_payment_profile_id: stripe_payment_method.id,
                    cc_type: stripe_payment_method.card.brand,
                    month: stripe_payment_method.card.exp_month,
                    year: stripe_payment_method.card.exp_year,
                    last_digits: stripe_payment_method.card.last4,
                    payment_method: payment_method
                  })
                end

                # Update payment to pending if authorised only, and completed if auto capture enabled
                if payment_intent['capture_method'] == "manual"
                  payment.update!(state: "pending")
                else
                  payment.update!(state: "completed")
                end

                # Update order status to complete
                order = payment.order
                order.next until cannot_make_transition?(order)
              end
            else
              puts "Unhandled event type: #{event.type}"
            end
            render json: { message: I18n.t('spree.stripe.response.success') }, status: :ok
          end
        
          def airwallex
            # require 'stripe'
            # Stripe.api_key = ::Spree::Gateway::StripeElementsGateway&.active.first.get_preference(:secret_key)
            endpoint_secret = ::Spree::Gateway::Airwallex&.active.first.get_preference(:endpoint_secret)

            payload = request.body.read
            timestamp = request.headers['x-timestamp']
            value_to_digest = timestamp + payload
            event = nil

            if endpoint_secret
              signature = OpenSSL::HMAC.hexdigest("SHA256", endpoint_secret, value_to_digest)
              puts "Spree signature is #{signature}"
              puts "Airwallex signature is #{request.headers['x-signature']}"
              if signature == request.headers['x-signature']
                begin
                  event = JSON.parse(payload, symbolize_names: true)
                rescue JSON::ParserError => e
                  # Invalid payload
                  puts "Webhook error while parsing request. #{e.message})"
                  status 400
                  return
                end
              else
                puts "Webhook signature verification failed."
                render json: { status: 400, error: "Webhook signature verification failed." }, status: :bad_request and return
              end
            else
              puts "No endpoint secret entered."
              status 400
            end

            # Handle the event
            case event[:name]
            when 'payment_intent.succeeded'
              puts "Payment for #{event[:data][:object][:amount]} succeeded."

              handle_payment_intent(event, "completed")
            when 'payment_intent.requires_capture'
              puts "Payment for #{event[:data][:object][:amount]} requires capture."

              handle_payment_intent(event, "pending")
            else
              puts "Unhandled event type: #{event[:name]}"
            end
            render json: { message: I18n.t('spree.stripe.response.success') }, status: :ok
          end
        
          private

          def cannot_make_transition?(order)
            order.complete? || order.errors.present?
          end
          
          def handle_payment_intent(event, end_state)
            aw_latest_payment = event[:data][:object][:latest_payment_attempt]
            aw_payment_method = aw_latest_payment[:payment_method][:card]
            
            payment = Spree::Payment.find_by(intent_id: event[:sourceId])
            
            if payment && (payment.state != end_state)
              payment_method = payment.payment_method
              # Create source using payment details from stripe payment element
              if payment.source.blank? && payment_method.try(:payment_source_class)
                payment.source = payment_method.payment_source_class.create!({
                  cc_type: aw_payment_method[:brand],
                  month: aw_payment_method[:expiry_month],
                  year: aw_payment_method[:expiry_year],
                  last_digits: aw_payment_method[:last4],
                  payment_method: payment_method
                })
              end

              payment.update!(state: end_state)
              
              # Update order status to complete
              order = payment.order
              order.next until cannot_make_transition?(order)
            end
          end
        end
      end
    end
  end
end
