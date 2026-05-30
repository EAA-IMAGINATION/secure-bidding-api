# frozen_string_literal: true

module SecureBidding
  module Services
    module Payments
      class FundEscrow
        def self.call(milestone:, payment_method_id: nil)
          return { ok: false, status: 400, error: 'milestone_id is required' } if milestone.nil?
          return { ok: false, status: 400, error: 'milestone is already funded' } if milestone.state == 'funded_escrow'

          reference = payment_method_id.to_s.strip
          reference = "placeholder-#{SecureRandom.hex(4)}" if reference.empty?

          payment = SecureBidding::Payment.create(
            milestone_id: milestone.id,
            project_id: milestone.project_id,
            payment_type: 'escrow_funding',
            status: 'held_in_escrow',
            method: 'placeholder',
            reference: reference,
            paid: true,
            paid_at: Time.now
          )
          milestone.update(state: 'funded_escrow')

          { ok: true, payment: payment, milestone: milestone }
        rescue Sequel::ValidationFailed, Sequel::ConstraintViolation => e
          { ok: false, status: 400, error: e.message }
        end
      end
    end
  end
end
