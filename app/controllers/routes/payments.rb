# frozen_string_literal: true

module SecureBidding
  module Routes
    # Handles payments endpoints and responses.
    module Payments
      def self.call(req, app)
        req.on 'payments' do
          handle_payments(req, app)
        end
      end

      def self.handle_payments(req, app)
        req.post true do
          create_payment(req, app)
        end

        req.on String do |id|
          req.get true do
            get_payment(req, app, id)
          end

          req.patch true do
            update_payment(req, app, id)
          end
        end
      end

      def self.create_payment(_req, app)
        policy = PaymentPolicy.new(app.auth_account, nil)
        unless policy.can_create?
          app.response.status = 403
          return { error: 'Forbidden: only logged in accounts can initiate payments' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Payments::CreatePayment.call(data)
        if result[:ok]
          app.response.status = 201
          app.payment_response(result[:payment])
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.get_payment(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Payment not found' }
        end

        payment = Payment[id]
        if payment.nil?
          app.response.status = 404
          return { error: 'Payment not found' }
        else
          policy = PaymentPolicy.new(app.auth_account, payment)
          unless policy.can_view?
            app.response.status = 403
            return { error: 'Forbidden: you do not have permission to view this payment' }
          end

          app.payment_response(payment)
        end
      end

      def self.update_payment(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Payment not found' }
        end

        payment = Payment[id]
        if payment.nil?
          app.response.status = 404
          return { error: 'Payment not found' }
        end

        policy = PaymentPolicy.new(app.auth_account, payment)
        unless policy.can_update?
          app.response.status = 403
          return { error: 'Forbidden: only admins can update payments' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Payments::UpdatePayment.call(payment: payment, payload: data)
        if result[:ok]
          app.payment_response(result[:payment])
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end
    end
  end
end
