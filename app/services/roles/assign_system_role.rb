# frozen_string_literal: true

module SecureBidding
  module Services
    module Roles
      # Assigns a named system role to an account.
      class AssignSystemRole
        PROMOTABLE_ACCOUNT_ROLES = %w[admin member].freeze

        def self.call(account_id:, role_name:)
          account = SecureBidding::Account[account_id]
          return { ok: false, status: 404, error: 'Account not found' } if account.nil?

          normalized_role_name = role_name.to_s
          if PROMOTABLE_ACCOUNT_ROLES.include?(normalized_role_name)
            account.update(system_role: normalized_role_name)
            return { ok: true, role: normalized_role_name }
          end

          EnsureRoles.call
          role = SecureBidding::Role.first(name: normalized_role_name)
          return { ok: false, status: 400, error: 'Unknown role' } if role.nil?

          SecureBidding::AccountRole.first(account_id: account.id, role_id: role.id) ||
            SecureBidding::AccountRole.create(account_id: account.id, role_id: role.id)

          { ok: true, role: role.name }
        end
      end
    end
  end
end
