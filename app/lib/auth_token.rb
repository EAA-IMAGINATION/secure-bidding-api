# frozen_string_literal: true

require 'json'
require 'time'

require_relative 'auth_scope'
require_relative 'securable'

module SecureBidding
  class ExpiredTokenError < StandardError; end
  class InvalidTokenError < StandardError; end

  class AuthToken
    extend Securable

    ONE_HOUR = 3600
    ONE_DAY = 86_400
    # Email verification links (registration, change-email, resend)
    VERIFICATION_LINK_TTL = ONE_DAY
    ONE_WEEK = 604_800
    ONE_MONTH = 2_592_000
    ONE_YEAR = 31_536_000

    def self.generate_key
      Securable.generate_key
    end

    def self.setup(base_key)
      setup_secret_key(base_key)
    end

    def self.encrypt(plaintext)
      base_encrypt(plaintext)
    end

    def self.decrypt(ciphertext64)
      base_decrypt(ciphertext64)
    end

    def self.tokenize(message, expiration = ONE_WEEK, scope: nil)
      new(message, expiration, scope: scope || AuthScope.new).to_s
    end

    def self.detokenize(ciphertext64)
      decrypted = decrypt(ciphertext64)
      JSON.parse(decrypted, symbolize_names: true)
    rescue StandardError => e
      raise InvalidTokenError, "Failed to decrypt or parse token: #{e.message}"
    end

    def self.load(token_string)
      token_data = detokenize(token_string)
      payload = token_data[:payload]
      scope_str = token_data[:scope] || AuthScope::FULL
      expiration = token_data[:exp]
      scope = AuthScope.new(scope_str)
      new(payload, expiration, scope: scope, from_encrypted: true)
    end

    def initialize(payload, expiration = ONE_WEEK, scope: nil, from_encrypted: false)
      @payload = payload
      @scope = scope || AuthScope.new

      @expiration = if from_encrypted
                      expiration
                    else
                      Time.now.to_i + expiration
                    end
    end

    def payload
      raise ExpiredTokenError, 'Token has expired' if expired?

      @payload
    end

    def scope
      raise ExpiredTokenError, 'Token has expired' if expired?

      @scope
    end

    def expired?
      raise InvalidTokenError, 'Token expiration is not an integer timestamp' unless @expiration.is_a?(Integer)

      Time.now.to_i >= @expiration
    end

    def fresh?
      !expired?
    end

    def to_s
      token_data = {
        'payload' => @payload,
        'scope' => @scope.to_s,
        'exp' => @expiration
      }
      json_str = JSON.generate(token_data)
      self.class.encrypt(json_str)
    end
  end
end
