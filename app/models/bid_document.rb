# frozen_string_literal: true

module SecureBidding
  # Represents an encrypted document attached to a bid submission.
  class BidDocument < Sequel::Model(:bid_documents)
    plugin :uuid, field: :id
    plugin :whitelist_security

    set_allowed_columns :bid_id, :file_name_secure, :file_hash, :storage_path

    many_to_one :bid_submission, class: 'SecureBidding::BidSubmission', key: :bid_id
  end
end
