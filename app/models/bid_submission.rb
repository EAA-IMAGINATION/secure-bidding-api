# frozen_string_literal: true

require_relative '../lib/secure_db'

module SecureBidding
  # Stores encrypted bid submissions associated with projects.
  class BidSubmission < Sequel::Model(:bid_submissions)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :project_id, :contractor_alias, :bidder_account_id, :encrypted_bid_amount,
                        :encrypted_proposal_text, :encrypted_document, :document_file_name, :document_file_hash

    many_to_one :bidder, key: :bidder_account_id, class: 'SecureBidding::Account'

    many_to_one :project, key: :project_id, class: 'SecureBidding::Project'
    one_to_many :payments, key: :bid_submission_id, class: 'SecureBidding::Payment'
    one_to_many :bid_documents, key: :bid_id, class: 'SecureBidding::BidDocument'

    def store_client_ciphertext(amount_envelope, proposal_envelope)
      self.encrypted_bid_amount = ClientCiphertext.normalize_envelope(amount_envelope)
      self.encrypted_proposal_text = ClientCiphertext.normalize_envelope(proposal_envelope)
    end

    def encrypt_bid(plaintext)
      self.secure_encrypted_bid = SecureDB.encrypt(plaintext)
    end

    def decrypt_bid
      SecureDB.decrypt(secure_encrypted_bid)
    end
  end
end
