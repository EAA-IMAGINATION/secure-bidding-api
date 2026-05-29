# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class BidSubmissionsCreateForm < BaseForm
      params do
        required(:project_id).filled(:string)
        required(:contractor_alias).filled(:string)
        required(:plaintext_bid).filled(:string)
      end

      rule(:project_id) do
        next if value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)

        key.failure('project_id must be a UUID')
      end
    end
  end
end
