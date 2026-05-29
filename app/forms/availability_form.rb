# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class AvailabilityForm < BaseForm
      params do
        optional(:username).maybe(:string)
        optional(:email).maybe(:string)
      end

      rule(:username, :email) do
        next if values[:username].to_s.strip.empty? == false || values[:email].to_s.strip.empty? == false

        base.failure('username or email is required')
      end
    end
  end
end
