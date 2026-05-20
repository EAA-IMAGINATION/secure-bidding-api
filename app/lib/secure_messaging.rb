# frozen_string_literal: true

require 'rbnacl'
require 'base64'

module SecureBidding
  # Simple secure messaging helper using libsodium's secretbox.
  class SecureMessaging
    NONCE_SIZE = RbNaCl::SecretBox.nonce_bytes

    def initialize(key = ENV.fetch('MSG_KEY', nil))
      raise ArgumentError, 'MSG_KEY is not set' if key.to_s.strip.empty?

      raw_key = Base64.decode64(key)
      unless raw_key.bytesize == RbNaCl::SecretBox.key_bytes
        raise ArgumentError, 'MSG_KEY must be a base64-encoded 32 byte key'
      end

      @box = RbNaCl::SecretBox.new(raw_key)
    end

    def encrypt(message)
      nonce = RbNaCl::Random.random_bytes(NONCE_SIZE)
      ciphertext = @box.encrypt(nonce, message.to_s)
      Base64.urlsafe_encode64(nonce + ciphertext)
    end

    def decrypt(token)
      data = Base64.urlsafe_decode64(token.to_s)
      nonce = data[0, NONCE_SIZE]
      ciphertext = data[NONCE_SIZE..]
      @box.decrypt(nonce, ciphertext)
    end
  end
end
