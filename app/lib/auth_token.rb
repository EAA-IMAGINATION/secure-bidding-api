# frozen_string_literal: true

require 'json'
require 'time'
require 'rbnacl'
require 'base64'

require_relative 'auth_scope'

module SecureBidding
  class ExpiredTokenError < StandardError; end
  class InvalidTokenError < StandardError; end

  class AuthToken
    ONE_HOUR = 3600
    ONE_DAY = 86_400
    ONE_WEEK = 604_800
    ONE_MONTH = 2_592_000
    ONE_YEAR = 31_536_000

    KEY_BYTES = 32

    class << self
      attr_accessor :auth_token_key
    end

    def self.generate_key
      random_bytes = RbNaCl::Random.random_bytes(KEY_BYTES)
      Base64.strict_encode64(random_bytes)
    end

    def self.setup(base_key)
      return nil if base_key.nil?

      self.auth_token_key = Base64.strict_decode64(base_key)
    end

    def self.encrypt(plaintext)
      raise NoKeyError, 'No secret key has been set up' if auth_token_key.nil?

      plaintext_bytes = plaintext.to_s.b
      cipher_box = RbNaCl::SimpleBox.from_secret_key(auth_token_key)
      ciphertext = cipher_box.encrypt(plaintext_bytes)
      Base64.strict_encode64(ciphertext)
    end

    def self.decrypt(ciphertext64)
      raise NoKeyError, 'No secret key has been set up' if auth_token_key.nil?
      return nil if ciphertext64.nil?

      ciphertext = Base64.strict_decode64(ciphertext64)
      cipher_box = RbNaCl::SimpleBox.from_secret_key(auth_token_key)
      plaintext_bytes = cipher_box.decrypt(ciphertext)
      plaintext_bytes.force_encoding('UTF-8')
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
