# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AccountsSearchForm < BaseForm
      params do
        optional(:email).maybe(:string)
        optional(:phone).maybe(:string)
      end

      rule(:email, :phone) do
        next if values[:email].to_s.strip.empty? == false || values[:phone].to_s.strip.empty? == false

        base.failure('email or phone query parameter is required')
      end
    end
  end
end
