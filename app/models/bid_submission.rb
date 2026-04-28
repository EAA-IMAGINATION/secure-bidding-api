# frozen_string_literal: true

require_relative '../lib/secure_db'

module SecureBidding
  # Stores encrypted bid submissions associated with projects.
  class BidSubmission < Sequel::Model(:bid_submissions)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :project_id, :contractor_alias

    many_to_one :project, key: :project_id, class: 'SecureBidding::Project'
    one_to_many :payments, key: :bid_submission_id, class: 'SecureBidding::Payment'

    def encrypt_bid(plaintext)
      self.secure_encrypted_bid = SecureDB.encrypt(plaintext)
    end

    def decrypt_bid
      SecureDB.decrypt(secure_encrypted_bid)
    end
  end
end
