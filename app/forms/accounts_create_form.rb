# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AccountsCreateForm < BaseForm
      params do
        required(:username).filled(:string)
        required(:password).filled(:string)
        required(:email).filled(:string)
        optional(:phone).maybe(:string)
        optional(:system_role).maybe(:string)
      end
    end
  end
end
