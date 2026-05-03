# frozen_string_literal: true

module SecureBidding
  module Services
    module Roles
      # Assigns a named system role to an account.
      class AssignSystemRole
        def self.call(account_id:, role_name:)
          account = SecureBidding::Account[account_id]
          return { ok: false, status: 404, error: 'Account not found' } if account.nil?

          EnsureRoles.call
          role = SecureBidding::Role.first(name: role_name.to_s)
          return { ok: false, status: 400, error: 'Unknown role' } if role.nil?

          SecureBidding::AccountRole.first(account_id: account.id, role_id: role.id) ||
            SecureBidding::AccountRole.create(account_id: account.id, role_id: role.id)

          { ok: true, role: role.name }
        end
      end
    end
  end
end
