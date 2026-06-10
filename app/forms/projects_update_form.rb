# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class ProjectsUpdateForm < BaseForm
      params do
        optional(:title).maybe(:string)
        optional(:budget_cents).maybe(:integer)
        optional(:description).maybe(:string)
        optional(:required_documents).maybe(:array)
        optional(:state).maybe(:string)
      end

      rule(:state) do
        next if value.nil? || SecureBidding::Project::VALID_STATES.include?(value.to_s)

        key.failure("state must be 'saved' or 'published'")
      end

      rule(:budget_cents) do
        next if value.nil? || (value.is_a?(Integer) && value >= 0)

        key.failure('budget_cents must be a non-negative integer')
      end

      rule do
        next if values.values.any? { |value| !value.nil? && !value.to_s.strip.empty? }

        base.failure('At least one updatable field is required')
      end
    end
  end
end
