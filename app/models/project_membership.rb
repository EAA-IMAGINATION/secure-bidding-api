# frozen_string_literal: true

module SecureBidding
  # Join model linking accounts to projects under a role.
  class ProjectMembership < Sequel::Model(:project_memberships)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :account_id, :project_id, :role_id

    many_to_one :account, key: :account_id, class: 'SecureBidding::Account'
    many_to_one :project, key: :project_id, class: 'SecureBidding::Project'
    many_to_one :role, key: :role_id, class: 'SecureBidding::Role'
  end
end
