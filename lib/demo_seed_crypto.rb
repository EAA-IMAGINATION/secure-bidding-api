# frozen_string_literal: true

require 'rbnacl'
require 'base64'
require 'digest'
require 'json'

module SecureBidding
  # Deterministic NaCl envelopes for development seeds (browser-compatible).
  module DemoSeedCrypto
    module_function

    def keypair_for(label)
      seed = Digest::SHA256.digest("secure-bidding-demo-#{label}")
      private_key = RbNaCl::PrivateKey.new(seed)
      {
        public_key_b64: Base64.strict_encode64(private_key.public_key.to_bytes),
        secret_bytes: private_key.to_bytes,
        private_key: private_key
      }
    end

    def wrap_private_key(secret_bytes, label)
      wrap_key = Digest::SHA256.digest("secure-bidding-wrap-#{label}")
      wrap_nonce = Digest::SHA256.digest("secure-bidding-wrap-nonce-#{label}")[0, RbNaCl::SecretBox.nonce_bytes]
      ciphertext = RbNaCl::SecretBox.new(wrap_key).encrypt(wrap_nonce, secret_bytes)
      JSON.generate(
        {
          key: Base64.strict_encode64(wrap_key),
          nonce: Base64.strict_encode64(wrap_nonce),
          ciphertext: Base64.strict_encode64(ciphertext)
        }
      )
    end

    def encrypt_for_project(private_key, plaintext, label)
      eph_seed = Digest::SHA256.digest("secure-bidding-eph-#{label}")
      ephemeral = RbNaCl::PrivateKey.new(eph_seed)
      nonce = Digest::SHA256.digest("secure-bidding-box-nonce-#{label}")[0, RbNaCl::Box.nonce_bytes]
      box = RbNaCl::Box.new(ephemeral.public_key, private_key)
      ciphertext = box.encrypt(nonce, plaintext.to_s)
      {
        'ephemeralPublicKey' => Base64.strict_encode64(ephemeral.public_key.to_bytes),
        'nonce' => Base64.strict_encode64(nonce),
        'ciphertext' => Base64.strict_encode64(ciphertext)
      }
    end
  end
end
