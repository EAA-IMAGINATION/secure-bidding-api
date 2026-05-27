# frozen_string_literal: true

module SecureBidding
  module Services
    module Roles
      # Ensures baseline role records exist.
      class EnsureRoles
        DEFAULT_ROLES = %w[system_admin project_owner bidder].freeze

        def self.call
          DEFAULT_ROLES.each do |role_name|
            SecureBidding::Role.first(name: role_name) || SecureBidding::Role.create(name: role_name)
          end
        end
      end
    end
  end
end
