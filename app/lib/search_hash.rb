# frozen_string_literal: true

require 'openssl'
require_relative '../../config/secrets'

module SecureBidding
  # Generates keyed hashes for searchable encrypted fields.
  module SearchHash
    module_function

    def digest(value, env = SecureBidding::Environment.app_env)
      normalized = value.to_s.strip.downcase
      OpenSSL::HMAC.hexdigest(
        'SHA256',
        SecureBidding::SecretsConfig.database_key(env).to_s.b,
        normalized
      )
    end
  end
end
