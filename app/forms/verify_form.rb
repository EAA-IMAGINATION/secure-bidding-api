# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class VerifyForm < BaseForm
      params do
        required(:registration_token).filled(:string)
        required(:password).filled(:string)
      end
    end
  end
end
