# frozen_string_literal: true

module SecureBidding
  module Services
    module Payments
      class ReleaseEscrow
        def self.call(milestone:)
          return { ok: false, status: 400, error: 'milestone_id is required' } if milestone.nil?

          escrow_payment = SecureBidding::Payment.where(
            milestone_id: milestone.id,
            payment_type: 'escrow_funding',
            status: 'held_in_escrow'
          ).order(Sequel.desc(:paid_at)).first

          return { ok: false, status: 400, error: 'No escrow funds are held for this milestone' } if escrow_payment.nil?

          escrow_payment.update(status: 'released')
          milestone.update(state: 'released')

          { ok: true, payment: escrow_payment, milestone: milestone }
        end
      end
    end
  end
end
