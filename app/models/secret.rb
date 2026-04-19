# frozen_string_literal: true

require_relative '../lib/secure_db'

module SecureBidding
  class Secret < Sequel::Model(:secrets)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :account_id, :title

    many_to_one :account, key: :account_id, class: 'SecureBidding::Account'

    def encrypt_data(plaintext)
      self.secure_encrypted_data = SecureDB.encrypt(plaintext)
    end

    def decrypt_data
      SecureDB.decrypt(secure_encrypted_data)
    end
  end
end
