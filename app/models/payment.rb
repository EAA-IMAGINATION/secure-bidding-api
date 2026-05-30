# frozen_string_literal: true

module SecureBidding
  # Placeholder payment status associated with a bid submission.
  class Payment < Sequel::Model(:payments)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :bid_submission_id, :paid, :method, :reference, :paid_at,
                        :milestone_id, :project_id, :recipient_id, :payment_type, :status,
                        :gateway_transaction_id

    many_to_one :bid_submission, key: :bid_submission_id, class: 'SecureBidding::BidSubmission'
    many_to_one :milestone, key: :milestone_id, class: 'SecureBidding::Milestone'
    many_to_one :project, key: :project_id, class: 'SecureBidding::Project'
  end
end
