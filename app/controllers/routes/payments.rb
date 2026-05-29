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
        data = app.parse_json_request_body
        return data if app.response.status == 400

        SecureBidding::Forms::PaymentsCreateForm.new.call(data)
        result = SecureBidding::Services::Payments::CreatePayment.call(data.transform_keys(&:to_s))
        if result[:ok]
          app.response.status = 201
          app.payment_response(result[:payment], policy: app.payment_policy(result[:payment]))
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
        if payment && app.payment_policy(payment).show?
          app.payment_response(payment, policy: app.payment_policy(payment))
        else
          app.response.status = 404
          { error: 'Payment not found' }
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

        data = app.parse_json_request_body
        return data if app.response.status == 400

        SecureBidding::Forms::PaymentsUpdateForm.new.call(data)
        result = SecureBidding::Services::Payments::UpdatePayment.call(payment: payment, payload: data.transform_keys(&:to_s))
        if result[:ok]
          app.payment_response(result[:payment], policy: app.payment_policy(result[:payment]))
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end
    end
  end
end
