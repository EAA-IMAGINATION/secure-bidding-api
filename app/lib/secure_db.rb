# frozen_string_literal: true

require 'rbnacl'
require_relative '../../config/secrets'

module SecureBidding
  module SecureDB
    module_function

    def encrypt(plaintext, env = SecureBidding::Environment.app_env)
      cipher_for_env(env).encrypt(plaintext.to_s.b)
    end

    def decrypt(ciphertext, env = SecureBidding::Environment.app_env)
      cipher_for_env(env).decrypt(ciphertext).force_encoding('UTF-8')
    end

    def cipher_for_env(env)
      RbNaCl::SimpleBox.from_secret_key(SecureBidding::SecretsConfig.database_key(env).to_s.b)
    end
  end
end
