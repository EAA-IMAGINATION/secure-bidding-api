# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class ProjectsCreateForm < BaseForm
      params do
        required(:title).filled(:string)
        required(:budget_cents).filled(:integer)
        optional(:description).maybe(:string)
        optional(:required_documents).maybe(:array)
        optional(:state).maybe(:string)
      end

      rule(:state) do
        next if value.nil? || SecureBidding::Project::VALID_STATES.include?(value.to_s)

        key.failure("state must be 'saved' or 'published'")
      end

      rule(:budget_cents) do
        next if value.is_a?(Integer) && value >= 0

        key.failure('budget_cents must be a non-negative integer')
      end
    end
  end
end
