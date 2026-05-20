# frozen_string_literal: true

module SecureBidding
  # Join model that links accounts to project collaborations.
  class AccountProject < Sequel::Model(:account_projects)
    plugin :whitelist_security
    set_allowed_columns :account_id, :project_id, :collaboration_role

    many_to_one :account, key: :account_id, class: 'SecureBidding::Account'
    many_to_one :project, key: :project_id, class: 'SecureBidding::Project'
  end
end
