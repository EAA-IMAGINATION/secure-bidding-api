# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class RegisterForm < BaseForm
      params do
        required(:username).filled(:string)
        required(:email).filled(:string)
      end
    end
  end
end
