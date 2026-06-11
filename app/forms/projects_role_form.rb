# frozen_string_literal: true

require_relative 'base_form'

module SecureBidding
  module Forms
    class ProjectsRoleForm < BaseForm
      params do
        optional(:account_id).maybe(:string)
        optional(:username).maybe(:string)
        required(:role).filled(:string)
      end

      rule(:account_id, :username) do
        account_id = values[:account_id].to_s.strip
        username = values[:username].to_s.strip
        next unless account_id.empty? && username.empty?

        key(:username).failure('username or account_id is required')
      end
    end
  end
end
