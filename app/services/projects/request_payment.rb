# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      class RequestPayment
        def self.call(project_id:, auth_account:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          policy = SecureBidding::Policies::ProjectPolicy.new(auth_account, project)
          return { ok: false, status: 403, error: 'Not authorized to request payment' } unless policy.request_payment?

          project.update(state: 'payment_pending', payment_status: 'requested')
          { ok: true, project: project }
        end
      end
    end
  end
end
