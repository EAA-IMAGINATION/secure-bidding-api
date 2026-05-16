# frozen_string_literal: true

require 'json'
require 'time'
require 'rbnacl'
require 'base64'

module SecureBidding
  # Custom errors for AuthToken
  class ExpiredTokenError < StandardError; end
  class InvalidTokenError < StandardError; end

  # AuthToken library for JWT-like token creation, signing, parsing, and expiration validation.
  # Extends Securable module to use base_encrypt/base_decrypt for encryption.
  class AuthToken
    # Time constants in seconds
    ONE_HOUR = 3600
    ONE_DAY = 86_400
    ONE_WEEK = 604_800
    ONE_MONTH = 2_592_000
    ONE_YEAR = 31_536_000

    # NaCl secret box key size in bytes
    KEY_BYTES = 32

    class << self
      # Private: instance variable for shared key state
      attr_accessor :auth_token_key
    end

    # Generate a new random key for encryption or hashing
    # @return [String] Base64-encoded random bytes (32 bytes for NaCl)
    def self.generate_key
      random_bytes = RbNaCl::Random.random_bytes(KEY_BYTES)
      Base64.strict_encode64(random_bytes)
    end

    # Setup the AuthToken with a Base64-encoded encryption key
    # @param base_key [String] Base64-encoded encryption key
    # @return [void]
    def self.setup(base_key)
      return nil if base_key.nil?

      self.auth_token_key = Base64.strict_decode64(base_key)
    end

    # Encrypt plaintext using RbNaCl::SimpleBox
    # @param plaintext [String] The text to encrypt
    # @return [String] Base64-encoded ciphertext
    # @raise [NoKeyError] If no secret key has been set up
    def self.encrypt(plaintext)
      raise NoKeyError, 'No secret key has been set up' if auth_token_key.nil?

      plaintext_bytes = plaintext.to_s.b
      cipher_box = RbNaCl::SimpleBox.from_secret_key(auth_token_key)
      ciphertext = cipher_box.encrypt(plaintext_bytes)
      Base64.strict_encode64(ciphertext)
    end

    # Decrypt Base64-encoded ciphertext using RbNaCl::SimpleBox
    # @param ciphertext64 [String] Base64-encoded ciphertext
    # @return [String] Decrypted plaintext as UTF-8 string
    # @raise [NoKeyError] If no secret key has been set up
    def self.decrypt(ciphertext64)
      raise NoKeyError, 'No secret key has been set up' if auth_token_key.nil?
      return nil if ciphertext64.nil?

      ciphertext = Base64.strict_decode64(ciphertext64)
      cipher_box = RbNaCl::SimpleBox.from_secret_key(auth_token_key)
      plaintext_bytes = cipher_box.decrypt(ciphertext)
      plaintext_bytes.force_encoding('UTF-8')
    end

    # Create an encrypted token from a payload
    # @param message [Object] Payload to encrypt (will be JSON-serialized)
    # @param expiration [Integer] Optional custom expiration time in seconds (default: ONE_WEEK)
    # @return [String] Base64-encoded token string
    def self.tokenize(message, expiration = ONE_WEEK)
      token = new(message, expiration)
      token.to_s
    end

    # Decrypt and parse a token string
    # @param ciphertext64 [String] Base64-encoded token string
    # @return [Hash] Decrypted token data with 'payload' and 'exp' keys
    # @raise [InvalidTokenError] If decryption or JSON parsing fails
    def self.detokenize(ciphertext64)
      decrypted = decrypt(ciphertext64)
      # Use symbolize_names to preserve symbol keys in the payload
      JSON.parse(decrypted, symbolize_names: true)
    rescue StandardError => e
      raise InvalidTokenError, "Failed to decrypt or parse token: #{e.message}"
    end

    # Load an AuthToken instance from a token string
    # @param token_string [String] Base64-encoded token string
    # @return [AuthToken] Token instance
    def self.load(token_string)
      token_data = detokenize(token_string)
      payload = token_data[:payload]
      expiration = token_data[:exp]
      new(payload, expiration, from_encrypted: true)
    end

    # Initialize an AuthToken with a payload and expiration
    # @param payload [Object] The data to carry in the token
    # @param expiration [Integer] Expiration time in seconds or timestamp (default: ONE_WEEK)
    # @param from_encrypted [Boolean] Internal flag for loading from encrypted token
    def initialize(payload, expiration = ONE_WEEK, from_encrypted: false)
      @payload = payload
      
      # If from_encrypted, expiration is already a timestamp; otherwise it's a duration
      if from_encrypted
        @expiration = expiration
      else
        @expiration = Time.now.to_i + expiration
      end
    end

    # Get the payload if the token is fresh
    # @return [Object] The token payload
    # @raise [ExpiredTokenError] If the token is expired
    def payload
      raise ExpiredTokenError, 'Token has expired' if expired?

      @payload
    end

    # Check if the token is expired
    # @return [Boolean] True if expired, false otherwise
    # @raise [InvalidTokenError] If expiration is not an Integer
    def expired?
      raise InvalidTokenError, 'Token expiration is not an integer timestamp' unless @expiration.is_a?(Integer)

      Time.now.to_i >= @expiration
    end

    # Check if the token is fresh (not expired)
    # @return [Boolean] True if fresh, false otherwise
    def fresh?
      !expired?
    end

    # Convert the token to its Base64-encoded string representation
    # @return [String] Base64-encoded encrypted token
    def to_s
      token_data = {
        'payload' => @payload,
        'exp' => @expiration
      }
      json_str = JSON.generate(token_data)
      self.class.encrypt(json_str)
    end
  end
end



