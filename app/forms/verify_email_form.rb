# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class VerifyEmailForm < BaseForm
      params do
        required(:registration_token).filled(:string)
      end
    end
  end
end
