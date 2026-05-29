# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class PaymentsCreateForm < BaseForm
      params do
        required(:bid_submission_id).filled(:string)
        optional(:paid).maybe(:bool)
        optional(:method).maybe(:string)
        optional(:reference).maybe(:string)
      end

      rule(:bid_submission_id) do
        next if value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)

        key.failure('bid_submission_id must be a UUID')
      end
    end
  end
end
