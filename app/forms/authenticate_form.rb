# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AuthenticateForm < BaseForm
      params do
        required(:username).filled(:string)
        required(:password).filled(:string)
      end
    end
  end
end
