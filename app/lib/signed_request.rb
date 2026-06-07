# frozen_string_literal: true

require 'rbnacl'
require 'base64'

module SecureBidding
  # Verifies digitally signed requests from the web app.
  class SignedRequest
    class VerificationError < StandardError; end
    class KeypairError < StandardError; end

    # Signing half is optional: only clients (and test) hold SIGNING_KEY.
    def self.setup(verify_key64, signing_key64 = nil)
      @verify_key = Base64.strict_decode64(verify_key64)
      @signing_key = signing_key64 ? Base64.strict_decode64(signing_key64) : nil
    rescue StandardError
      raise KeypairError, 'Invalid verification/signing keypair'
    end

    def self.generate_keypair
      signing_key = RbNaCl::SigningKey.generate
      verify_key = signing_key.verify_key

      {
        signing_key: Base64.strict_encode64(signing_key.to_bytes),
        verify_key: Base64.strict_encode64(verify_key.to_bytes)
      }
    end

    def self.parse(signed)
      data = signed[:data] || signed['data']
      signature = signed[:signature] || signed['signature']
      raise VerificationError if data.nil? || signature.to_s.empty?

      data if verify(data, signature)
    end

    def self.sign(message)
      raise KeypairError, 'No signing key configured' unless @signing_key

      signature = RbNaCl::SigningKey.new(@signing_key)
        .sign(message.to_json)
        .then { |sig| Base64.strict_encode64(sig) }

      { data: message, signature: signature }
    end

    def self.verify(message, signature64)
      signature = Base64.strict_decode64(signature64)
      verifier = RbNaCl::VerifyKey.new(@verify_key)
      verifier.verify(signature, message.to_json)
    rescue StandardError
      raise VerificationError
    end
  end
end
