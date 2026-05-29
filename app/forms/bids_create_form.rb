# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class BidsCreateForm < BaseForm
      params do
        required(:contractor).filled(:string)
        required(:project_id).filled(:string)
        required(:encrypted_bid).filled(:string)
      end

      rule(:encrypted_bid) do
        next unless value.to_s.strip.empty?

        key.failure('encrypted_bid is required and cannot be empty')
      end
    end
  end
end
