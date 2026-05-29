# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class PaymentsUpdateForm < BaseForm
      params do
        optional(:paid).maybe(:bool)
        optional(:method).maybe(:string)
        optional(:reference).maybe(:string)
      end

      rule do
        next if values.values.any? { |value| !value.nil? && !value.to_s.strip.empty? }

        base.failure('At least one updatable field is required')
      end
    end
  end
end
