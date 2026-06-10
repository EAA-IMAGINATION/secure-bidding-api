# frozen_string_literal: true

module SecureBidding
  # Represents a project that can receive bid submissions.
  class Project < Sequel::Model(:projects)
    VALID_STATES = %w[saved published in_progress payment_pending closed].freeze
    PAYMENT_STATUSES = %w[none requested in_process acknowledged].freeze

    plugin :uuid, field: :id
    plugin :whitelist_security
    plugin :association_dependencies
    set_allowed_columns :title, :description, :required_documents, :budget_cents, :state, :bidding_deadline, :nacl_public_key,
                        :nacl_encrypted_private_key, :awarded_bid_submission_id, :payment_status,
                        :awarded_bid_amount_cents, :payment_amount_cents

    many_to_one :awarded_bid_submission, key: :awarded_bid_submission_id, class: 'SecureBidding::BidSubmission'

    one_to_many :bid_submissions, key: :project_id, class: 'SecureBidding::BidSubmission'
    one_to_many :account_projects, key: :project_id, class: 'SecureBidding::AccountProject'
    one_to_many :project_memberships, key: :project_id, class: 'SecureBidding::ProjectMembership'
    one_to_many :milestones, key: :project_id, class: 'SecureBidding::Milestone'

    many_to_many :collaborators,
                 class: 'SecureBidding::Account',
                 join_table: :account_projects,
                 left_key: :project_id,
                 right_key: :account_id
    many_to_many :members,
                 class: 'SecureBidding::Account',
                 join_table: :project_memberships,
                 left_key: :project_id,
                 right_key: :account_id

    add_association_dependencies bid_submissions: :delete, account_projects: :delete, project_memberships: :delete, milestones: :delete
  end
end
