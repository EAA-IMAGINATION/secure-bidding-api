# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      class AcknowledgePayment
        def self.call(project_id:, auth_account:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          policy = SecureBidding::Policies::ProjectPolicy.new(auth_account, project)
          return { ok: false, status: 403, error: 'Not authorized to close project' } unless policy.acknowledge_payment?

          project.update(state: 'closed', payment_status: 'acknowledged')
          { ok: true, project: project }
        end
      end
    end
  end
end
