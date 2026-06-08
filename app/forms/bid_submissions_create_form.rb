# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class BidSubmissionsCreateForm < BaseForm
      params do
        required(:project_id).filled(:string)
        required(:contractor_alias).filled(:string)
        required(:encrypted_bid_amount)
        required(:encrypted_proposal_text)
      end

      rule(:project_id) do
        next if value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)

        key.failure('project_id must be a UUID')
      end

      rule(:encrypted_bid_amount) do
        key.failure('encrypted_bid_amount must be a valid NaCl envelope') unless ClientCiphertext.valid_envelope?(value)
      end

      rule(:encrypted_proposal_text) do
        key.failure('encrypted_proposal_text must be a valid NaCl envelope') unless ClientCiphertext.valid_envelope?(value)
      end
    end
  end
end
