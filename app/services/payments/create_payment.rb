# frozen_string_literal: true

module SecureBidding
  module Services
    module Payments
      # Creates a placeholder payment linked to a bid submission.
      class CreatePayment
        UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

        def self.call(payload)
          bid_submission_id = payload['bid_submission_id']
          if bid_submission_id.to_s.strip.empty?
            return { ok: false, status: 400,
                     error: 'bid_submission_id is required' }
          elsif !uuid?(bid_submission_id)
            return { ok: false, status: 400,
                     error: 'bid_submission_id must be a UUID' }
          end

          bid_submission = SecureBidding::BidSubmission[bid_submission_id]
          if bid_submission.nil?
            return { ok: false, status: 400,
                     error: 'bid_submission_id must reference an existing bid submission' }
          end

          payment = SecureBidding::Payment.new(
            bid_submission_id: bid_submission.id,
            paid: payload['paid'],
            method: payload['method'],
            reference: payload['reference']
          )
          payment.paid = false if payment.paid.nil?
          payment.paid_at = Time.now if payment.paid
          payment.save
          { ok: true, payment: payment }
        rescue Sequel::UniqueConstraintViolation
          { ok: false, status: 400, error: 'payment already exists for bid submission' }
        end

        def self.uuid?(value)
          value.to_s.match?(UUID_FORMAT)
        end
      end
    end
  end
end
