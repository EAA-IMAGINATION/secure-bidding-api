# frozen_string_literal: true

module SecureBidding
  module Services
    module Payments
      # Updates placeholder payment status and metadata.
      class UpdatePayment
        def self.call(payment:, payload:)
          if payload.nil? || payload.empty?
            return { ok: false, status: 400,
                     error: 'At least one updatable field is required' }
          end

          paid = payload['paid']
          method = payload['method']
          reference = payload['reference']

          payment.paid = paid unless paid.nil?
          payment[:method] = method unless method.nil?
          payment.reference = reference unless reference.nil?
          payment.paid_at = Time.now if paid == true
          payment.paid_at = nil if paid == false
          payment.save
          { ok: true, payment: payment }
        end
      end
    end
  end
end
