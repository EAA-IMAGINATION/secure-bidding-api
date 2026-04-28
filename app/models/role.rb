# frozen_string_literal: true

module SecureBidding
  # Models a named system or project-scoped role.
  class Role < Sequel::Model(:roles)
    one_to_many :account_roles, key: :role_id, class: 'SecureBidding::AccountRole'
    one_to_many :project_memberships, key: :role_id, class: 'SecureBidding::ProjectMembership'
  end
end
