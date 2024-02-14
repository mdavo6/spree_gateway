module Spree
  module Api
    module V2
      module Storefront
        class IntentsController < ::Spree::Api::V2::BaseController
          include Spree::Api::V2::Storefront::OrderConcern
          #before_action :ensure_order

          def create
            spree_current_order = Spree::Order.find(params[:order_id])
            options = {}
            options[:merchant_order_id] = params[:order_id]
            options[:currency] = params[:currency]

            spree_authorize! :update, spree_current_order, order_token
            
            payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
            
            payment_intent = payment_method.create_intent(spree_current_order.display_outstanding_balance.money, options)

            spree_current_order.payments.create(
              amount: payment_intent.params["amount"],
              payment_method_id: payment_method.id, 
              intent_id: payment_intent.params["id"])

            #spree_current_order.reload
            #last_valid_payment = spree_current_order.payments.valid.where.not(intent_client_key: nil).last
            if payment_intent.present?
              #publishable_key = last_valid_payment.payment_method&.preferred_publishable_key
              #payment_id = last_valid_payment.id
              return render json: {
                intentId: payment_intent.params["id"],
                clientSecret: payment_intent.params["client_secret"],
                currency: payment_intent.params["currency"]
                #payment_id: payment_id,
              }, status: :ok
            end

            render_error_payload(I18n.t('spree.no_payment_intent_created'))
          end

          def payment_confirmation_data
            spree_authorize! :update, spree_current_order, order_token

            if spree_current_order.intents?
              spree_current_order.process_payments!
              spree_current_order.reload
              last_valid_payment = spree_current_order.payments.valid.where.not(intent_client_key: nil).last

              if last_valid_payment.present?
                client_secret = last_valid_payment.intent_client_key
                publishable_key = last_valid_payment.payment_method&.preferred_publishable_key
                return render json: { client_secret: client_secret, pk_key: publishable_key }, status: :ok
              end
            end

            render_error_payload(I18n.t('spree.no_payment_authorization_needed'))
          end

          def handle_response
            if params['response']['error']
              invalidate_payment
              render_error_payload(params['response']['error']['message'])
            else
              render_serialized_payload { { message: I18n.t('spree.payment_successfully_authorized') } }
            end
          end

          private

          def invalidate_payment
            payment = spree_current_order.payments.find_by!(response_code: params['response']['error']['payment_intent']['id'])
            payment.update(state: 'failed', intent_client_key: nil)
          end
        end
      end
    end
  end
end
