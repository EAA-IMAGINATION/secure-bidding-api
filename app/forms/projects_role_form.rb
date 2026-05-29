# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class ProjectsRoleForm < BaseForm
      params do
        required(:account_id).filled(:string)
        required(:role).filled(:string)
      end
    end
  end
end
