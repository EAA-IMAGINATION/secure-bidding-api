# frozen_string_literal: true

require 'rbnacl'
require 'base64'

module SecureBidding
  # Custom errors for Securable module
  class NoKeyError < StandardError; end
  class NoHashKeyError < StandardError; end

  # Securable module provides shared cryptographic primitives for encryption and hashing.
  # Both SecureDB and AuthToken extend this module.
  module Securable
    module_function

    # NaCl secret box key size in bytes
    KEY_BYTES = 32

    # Generate a new random key for encryption or hashing
    # @return [String] Base64-encoded random bytes (32 bytes for NaCl)
    def generate_key
      random_bytes = RbNaCl::Random.random_bytes(KEY_BYTES)
      Base64.strict_encode64(random_bytes)
    end

    # Set up the secret key for encryption
    # @param secret_key [String] Base64-encoded secret key
    # @return [void]
    def setup_secret_key(secret_key)
      return nil if secret_key.nil?

      @key = Base64.strict_decode64(secret_key)
    end

    # Set up the hash key for HMAC operations
    # @param hash_key [String] Base64-encoded hash key
    # @return [void]
    def setup_hash_key(hash_key)
      return nil if hash_key.nil?

      @hash_key = Base64.strict_decode64(hash_key)
    end

    # Get the current secret key
    # @return [String] Decoded secret key (raw bytes)
    # @raise [NoKeyError] If no key has been set up
    def key
      raise NoKeyError, 'No secret key has been set up' if @key.nil?

      @key
    end

    # Encrypt plaintext using RbNaCl::SimpleBox
    # @param plaintext [String] The text to encrypt
    # @return [String] Base64-encoded ciphertext
    # @raise [NoKeyError] If no secret key has been set up
    def base_encrypt(plaintext)
      raise NoKeyError, 'No secret key has been set up' if @key.nil?

      plaintext_bytes = plaintext.to_s.b
      cipher_box = RbNaCl::SimpleBox.from_secret_key(@key)
      ciphertext = cipher_box.encrypt(plaintext_bytes)
      Base64.strict_encode64(ciphertext)
    end

    # Decrypt Base64-encoded ciphertext using RbNaCl::SimpleBox
    # @param ciphertext64 [String] Base64-encoded ciphertext
    # @return [String] Decrypted plaintext as UTF-8 string
    # @raise [NoKeyError] If no secret key has been set up
    def base_decrypt(ciphertext64)
      raise NoKeyError, 'No secret key has been set up' if @key.nil?
      return nil if ciphertext64.nil?

      ciphertext = Base64.strict_decode64(ciphertext64)
      cipher_box = RbNaCl::SimpleBox.from_secret_key(@key)
      plaintext_bytes = cipher_box.decrypt(ciphertext)
      plaintext_bytes.force_encoding('UTF-8')
    end

    # Hash plaintext using RbNaCl::HMAC::SHA256
    # @param plaintext [String] The text to hash
    # @return [String] Base64-encoded HMAC digest
    # @raise [NoHashKeyError] If no hash key has been set up
    def base_hash(plaintext)
      raise NoHashKeyError, 'No hash key has been set up' if @hash_key.nil?

      plaintext_bytes = plaintext.to_s.b
      hmac = RbNaCl::HMAC::SHA256.new(@hash_key)
      hmac.update(plaintext_bytes)
      digest = hmac.digest
      Base64.strict_encode64(digest)
    end
  end
end
