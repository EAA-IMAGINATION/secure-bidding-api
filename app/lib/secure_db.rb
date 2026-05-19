# frozen_string_literal: true

require 'base64'
require_relative '../../config/secrets'
require_relative 'securable'

module SecureBidding
  # Encrypts and decrypts sensitive database payloads using the configured DB key.
  # Uses Securable module for shared cryptographic primitives.
  module SecureDB
    extend Securable
    module_function

    def encrypt(plaintext, env = SecureBidding::Environment.app_env)
      setup_key_for_env(env)
      base_encrypt(plaintext.to_s)
    end

    def decrypt(ciphertext, env = SecureBidding::Environment.app_env)
      setup_key_for_env(env)
      base_decrypt(ciphertext)
    end

    def setup_key_for_env(env)
      raw_key = SecureBidding::SecretsConfig.database_key(env).to_s.b
      encoded_key = Base64.strict_encode64(raw_key)
      setup_secret_key(encoded_key)
    end
  end
end
