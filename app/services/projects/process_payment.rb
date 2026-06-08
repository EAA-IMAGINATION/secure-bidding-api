# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      class ProcessPayment
        def self.call(project_id:, auth_account:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          policy = SecureBidding::Policies::ProjectPolicy.new(auth_account, project)
          return { ok: false, status: 403, error: 'Not authorized to process payment' } unless policy.process_payment?

          award_amount = project.awarded_bid_amount_cents
          return { ok: false, status: 400, error: 'awarded bid amount is missing' } if award_amount.nil?

          project.update(payment_status: 'in_process', payment_amount_cents: award_amount)
          { ok: true, project: project }
        end
      end
    end
  end
end
