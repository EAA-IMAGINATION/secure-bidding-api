# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'securerandom'

module SecureBidding
  # Provides PBKDF2 helpers for password hashing.
  module KeyStretching
    ITERATIONS = 200_000
    KEY_LENGTH = 64

    module_function

    def generate_salt
      SecureRandom.base64(32)
    end

    def stretch(secret, salt, iterations: ITERATIONS, key_length: KEY_LENGTH)
      stretched = OpenSSL::PKCS5.pbkdf2_hmac(
        secret.to_s,
        salt.to_s,
        iterations,
        key_length,
        'sha256'
      )
      Base64.strict_encode64(stretched)
    end
  end
end
