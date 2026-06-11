# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Ensures one account is the platform admin and demotes all other admin accounts.
      # Does not delete projects, bids, or memberships.
      class EnsurePlatformAdmin
        DEFAULT_USERNAME = 'scifiengineering'

        def self.call(platform_admin_username: DEFAULT_USERNAME)
          username = platform_admin_username.to_s.strip
          return { ok: false, status: 400, error: 'platform admin username is required' } if username.empty?

          admin_account = SecureBidding::Account.first(username: username)
          if admin_account.nil?
            return { ok: false, status: 404, error: "Account not found: #{username}" }
          end

          SecureBidding::Services::Roles::AssignSystemRole.call(
            account_id: admin_account.id,
            role_name: 'admin'
          )

          demoted = []
          SecureBidding::Account.where(system_role: 'admin').exclude(id: admin_account.id).each do |account|
            SecureBidding::Services::Roles::AssignSystemRole.call(
              account_id: account.id,
              role_name: 'member'
            )
            demoted << account.username
          end

          system_admin_role = SecureBidding::Role.first(name: 'system_admin')
          if system_admin_role
            SecureBidding::AccountRole
              .where(role_id: system_admin_role.id)
              .exclude(account_id: admin_account.id)
              .delete
          end

          {
            ok: true,
            platform_admin_username: admin_account.username,
            platform_admin_id: admin_account.id,
            demoted_usernames: demoted
          }
        end
      end
    end
  end
end
