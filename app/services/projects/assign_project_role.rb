# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      # Assigns an account to a project with a project-scoped role.
      class AssignProjectRole
        ALLOWED_ROLES = %w[project_owner bidder].freeze
        UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

        def self.call(project_id:, account_id:, role_name:, requested_by_admin:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          unless uuid?(account_id)
            return { ok: false, status: 400, error: 'account_id must be a UUID' }
          end

          account = SecureBidding::Account[account_id]
          return { ok: false, status: 404, error: 'Account not found' } if account.nil?

          normalized_role = role_name.to_s
          unless ALLOWED_ROLES.include?(normalized_role)
            return { ok: false, status: 400,
                     error: 'role must be project_owner or bidder' }
          end

          if normalized_role == 'project_owner'
            return assign_owner(project: project, account: account, requested_by_admin: requested_by_admin)
          end

          role = SecureBidding::Role.ensure_role(normalized_role)
          membership = SecureBidding::ProjectMembership.first(
            account_id: account.id,
            project_id: project.id,
            role_id: role.id
          ) || SecureBidding::ProjectMembership.create(
            account_id: account.id,
            project_id: project.id,
            role_id: role.id
          )

          { ok: true, membership: membership, role: role.name }
        end

        def self.assign_owner(project:, account:, requested_by_admin:)
          if requested_by_admin
            role = SecureBidding::Role.ensure_role('project_owner')
            membership = SecureBidding::ProjectMembership.first(
              account_id: account.id,
              project_id: project.id,
              role_id: role.id
            ) || SecureBidding::ProjectMembership.create(
              account_id: account.id,
              project_id: project.id,
              role_id: role.id
            )

            collaboration = SecureBidding::AccountProject.first(account_id: account.id, project_id: project.id)
            if collaboration
              collaboration.update(collaboration_role: 'owner') unless collaboration.collaboration_role == 'owner'
            else
              SecureBidding::AccountProject.create(
                account_id: account.id,
                project_id: project.id,
                collaboration_role: 'owner'
              )
            end

            return { ok: true, membership: membership, role: 'project_owner' }
          end

          collaboration = SecureBidding::AccountProject.first(account_id: account.id, project_id: project.id)
          if collaboration
            if collaboration.collaboration_role == 'owner'
              role = SecureBidding::Role.ensure_role('project_owner')
              membership = SecureBidding::ProjectMembership.first(
                account_id: account.id,
                project_id: project.id,
                role_id: role.id
              ) || SecureBidding::ProjectMembership.create(
                account_id: account.id,
                project_id: project.id,
                role_id: role.id
              )
              return { ok: true, membership: membership, role: 'project_owner' }
            end

            collaboration.update(collaboration_role: 'pending_owner') unless collaboration.collaboration_role == 'pending_owner'
          else
            collaboration = SecureBidding::AccountProject.create(
              account_id: account.id,
              project_id: project.id,
              collaboration_role: 'pending_owner'
            )
          end

          {
            ok: true,
            pending: true,
            request: {
              account_id: collaboration.account_id,
              project_id: collaboration.project_id,
              role: 'project_owner',
              status: 'pending'
            }
          }
        end

        def self.uuid?(value)
          value.to_s.match?(UUID_FORMAT)
        end
      end
    end
  end
end
