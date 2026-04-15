# frozen_string_literal: true

require 'rbnacl'

module SecureBidding
  class Secret < Sequel::Model(:secrets)
    many_to_one :account, key: :account_id, class: 'SecureBidding::Account'

    def encrypt_data(plaintext, key)
      self.encrypted_data = crypto_box(key).encrypt(plaintext.to_s.b)
    end

    def decrypt_data(key)
      crypto_box(key).decrypt(encrypted_data).force_encoding('UTF-8')
    end

    private

    def crypto_box(key)
      secret_key = key.to_s.b
      raise ArgumentError, 'key must be exactly 32 bytes' unless secret_key.bytesize == 32

      RbNaCl::SimpleBox.from_secret_key(secret_key)
    end
  end
end
