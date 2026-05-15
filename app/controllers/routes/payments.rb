# frozen_string_literal: true

module SecureBidding
  module Routes
    module Payments
      def self.call(r, app)
        r.on 'payments' do
          r.post true do
            data = app.parse_json_request_body
            if app.response.status == 400
              data
            else
              result = SecureBidding::Services::Payments::CreatePayment.call(data)
              if result[:ok]
                app.response.status = 201
                app.payment_response(result[:payment])
              else
                app.response.status = result[:status]
                { error: result[:error] }
              end
            end
          end

          r.on String do |id|
            r.get true do
              unless app.valid_uuid?(id)
                app.response.status = 404
                next { error: 'Payment not found' }
              end

              payment = Payment[id]
              if payment
                app.payment_response(payment)
              else
                app.response.status = 404
                { error: 'Payment not found' }
              end
            end

            r.patch true do
              unless app.valid_uuid?(id)
                app.response.status = 404
                next { error: 'Payment not found' }
              end

              payment = Payment[id]
              if payment.nil?
                app.response.status = 404
                { error: 'Payment not found' }
              else
                data = app.parse_json_request_body
                if app.response.status == 400
                  data
                else
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
        end
      end
    end
  end
end
