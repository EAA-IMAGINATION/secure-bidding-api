# frozen_string_literal: true

module SecureBidding
  # Represents a project that can receive bid submissions.
  class Project < Sequel::Model(:projects)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :title, :budget_cents

    one_to_many :bid_submissions, key: :project_id, class: 'SecureBidding::BidSubmission'
  end
end
