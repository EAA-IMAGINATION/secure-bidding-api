# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class ProjectsBidForm < BaseForm
      params do
        required(:bidder_account_id).filled(:string)
        required(:contractor_alias).filled(:string)
        required(:plaintext_bid).filled(:string)
      end

      rule(:bidder_account_id) do
        next if value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)

        key.failure('bidder_account_id must be a UUID')
      end
    end
  end
end
