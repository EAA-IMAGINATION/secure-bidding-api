# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AccountsSystemRoleForm < BaseForm
      params do
        required(:role).filled(:string)
      end

      rule(:role) do
        next if SecureBidding::Account::VALID_ROLES.include?(value.to_s)

        key.failure('role must be admin, member, system_admin, project_owner, or bidder')
      end
    end
  end
end
