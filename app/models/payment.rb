# frozen_string_literal: true

module SecureBidding
  # Placeholder payment status associated with a bid submission.
  class Payment < Sequel::Model(:payments)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :bid_submission_id, :paid, :method, :reference, :paid_at

    many_to_one :bid_submission, key: :bid_submission_id, class: 'SecureBidding::BidSubmission'
  end
end
