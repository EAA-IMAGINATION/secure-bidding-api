# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      # Creates a project requirement under an owner account policy.
      class CreateProjectRequirement
        def self.call(payload)
          owner_account_id = payload['owner_account_id']
          return { ok: false, status: 400, error: 'owner_account_id is required' } if owner_account_id.to_s.strip.empty?

          owner = SecureBidding::Account[owner_account_id]
          return { ok: false, status: 400, error: 'owner_account_id must reference an existing account' } if owner.nil?

          unless owner.system_role?('project_owner')
            return { ok: false, status: 403, error: 'owner account must have project_owner role' }
          end

          project = SecureBidding::Project.new
          project.set(
            title: payload['title'],
            budget_cents: payload['budget_cents']
          )
          project.save

          role = SecureBidding::Role.first(name: 'project_owner')
          SecureBidding::ProjectMembership.first(account_id: owner.id, project_id: project.id, role_id: role.id) ||
            SecureBidding::ProjectMembership.create(account_id: owner.id, project_id: project.id, role_id: role.id)

          { ok: true, project: project }
        rescue Sequel::MassAssignmentRestriction
          { ok: false, status: 400, error: 'Invalid project attributes' }
        rescue Sequel::UniqueConstraintViolation
          { ok: false, status: 400, error: 'project title must be unique' }
        end
      end
    end
  end
end
