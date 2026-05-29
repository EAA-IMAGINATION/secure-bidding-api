# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AccountsUpdateForm < BaseForm
      params do
        optional(:username).maybe(:string)
        optional(:password).maybe(:string)
        optional(:email).maybe(:string)
        optional(:phone).maybe(:string)
        optional(:system_role).maybe(:string)
      end

      rule(:system_role) do
        next if value.nil? || SecureBidding::Account::VALID_ROLES.include?(value.to_s)

        key.failure('system_role must be admin or member')
      end

      rule do
        next if values.values.any? { |value| !value.nil? && !value.to_s.strip.empty? }

        base.failure('At least one updatable field is required')
      end
    end
  end
end
